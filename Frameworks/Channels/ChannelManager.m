/*
 * OCChannelManager.m
 * LegacyPodClaw - Channel System Implementation
 *
 * Channel lifecycle, session routing, rate limiting, presence,
 * auto-reply, approval system, device pairing.
 */

#import "ChannelManager.h"

#pragma mark - Channel Message

@implementation OCChannelMessage
- (instancetype)init {
    if ((self = [super init])) { _timestamp = [[NSDate date] retain]; }
    return self;
}
- (void)dealloc {
    [_channelId release]; [_accountId release]; [_chatId release];
    [_threadId release]; [_senderId release]; [_senderName release];
    [_text release]; [_replyToId release]; [_attachmentURLs release];
    [_timestamp release]; [_messageId release];
    [super dealloc];
}
@end

#pragma mark - Session Router

@implementation OCSessionRouter

+ (NSString *)sessionKeyForMessage:(OCChannelMessage *)message agentId:(NSString *)agentId {
    NSString *agent = agentId ?: @"default";
    NSString *scope = message.isGroup ? @"group" : @"direct";
    NSString *peer = message.isDirect ? message.senderId : message.chatId;
    return [NSString stringWithFormat:@"agent:%@:%@:%@:%@",
            agent, scope, message.channelId, peer ?: @"unknown"];
}

+ (NSDictionary *)deliveryContextForMessage:(OCChannelMessage *)message {
    NSMutableDictionary *ctx = [NSMutableDictionary dictionaryWithCapacity:6];
    if (message.channelId) [ctx setObject:message.channelId forKey:@"channel"];
    if (message.chatId) [ctx setObject:message.chatId forKey:@"chatId"];
    if (message.threadId) [ctx setObject:message.threadId forKey:@"threadId"];
    if (message.senderId) [ctx setObject:message.senderId forKey:@"senderId"];
    if (message.senderName) [ctx setObject:message.senderName forKey:@"senderName"];
    [ctx setObject:@(message.isGroup) forKey:@"isGroup"];
    return ctx;
}

@end

#pragma mark - Channel Manager

@interface OCChannelManager () {
    NSMutableDictionary *_channelMap; /* channelId -> id<OCChannel> */
}
@end

@implementation OCChannelManager

- (instancetype)init {
    if ((self = [super init])) {
        _channelMap = [[NSMutableDictionary alloc] initWithCapacity:8];
    }
    return self;
}
- (void)dealloc { [_channelMap release]; [super dealloc]; }

- (void)registerChannel:(id<OCChannel>)channel {
    [_channelMap setObject:channel forKey:[channel channelId]];
}
- (void)removeChannel:(NSString *)channelId {
    id<OCChannel> ch = [_channelMap objectForKey:channelId];
    if (ch) { [ch stop]; [_channelMap removeObjectForKey:channelId]; }
}
- (id<OCChannel>)channelForId:(NSString *)channelId {
    return [_channelMap objectForKey:channelId];
}
- (NSArray *)channels { return [_channelMap allValues]; }
- (NSArray *)connectedChannels {
    NSMutableArray *a = [NSMutableArray array];
    for (id<OCChannel> ch in [_channelMap allValues]) {
        if ([ch isConnected]) [a addObject:ch];
    }
    return a;
}
- (void)startAll { for (id<OCChannel> ch in [_channelMap allValues]) [ch start]; }
- (void)stopAll { for (id<OCChannel> ch in [_channelMap allValues]) [ch stop]; }
- (void)startChannel:(NSString *)cid { [[_channelMap objectForKey:cid] start]; }
- (void)stopChannel:(NSString *)cid { [[_channelMap objectForKey:cid] stop]; }

- (void)sendMessage:(NSString *)text channelId:(NSString *)channelId
             chatId:(NSString *)chatId threadId:(NSString *)threadId {
    id<OCChannel> ch = [_channelMap objectForKey:channelId];
    if (ch) [ch sendMessage:text toChatId:chatId threadId:threadId];
}

- (void)broadcastMessage:(NSString *)text {
    for (id<OCChannel> ch in [_channelMap allValues]) {
        if ([ch isConnected]) [ch sendMessage:text toChatId:nil];
    }
}

- (NSDictionary *)allChannelStatus {
    NSMutableDictionary *status = [NSMutableDictionary dictionary];
    for (id<OCChannel> ch in [_channelMap allValues]) {
        NSMutableDictionary *s = [NSMutableDictionary dictionary];
        [s setObject:@([ch isConnected]) forKey:@"connected"];
        [s setObject:@([ch isConfigured]) forKey:@"configured"];
        if ([ch respondsToSelector:@selector(statusInfo)]) {
            NSDictionary *extra = [ch statusInfo];
            if (extra) [s addEntriesFromDictionary:extra];
        }
        [status setObject:s forKey:[ch channelId]];
    }
    return status;
}

@end

#pragma mark - Rate Limiter

@interface OCRateLimiter () {
    NSMutableDictionary *_buckets; /* ip -> NSMutableArray of NSDate */
    NSUInteger _maxRequests;
    NSTimeInterval _window;
}
@end

@implementation OCRateLimiter
- (instancetype)initWithMaxRequests:(NSUInteger)max perSeconds:(NSTimeInterval)window {
    if ((self = [super init])) {
        _maxRequests = max; _window = window;
        _buckets = [[NSMutableDictionary alloc] initWithCapacity:16];
    }
    return self;
}
- (void)dealloc { [_buckets release]; [super dealloc]; }

- (BOOL)allowRequestFromIP:(NSString *)ip {
    NSMutableArray *times = [_buckets objectForKey:ip];
    if (!times) { times = [NSMutableArray array]; [_buckets setObject:times forKey:ip]; }
    NSDate *now = [NSDate date];
    NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-_window];
    /* Prune old entries */
    while ([times count] > 0 && [[times objectAtIndex:0] compare:cutoff] == NSOrderedAscending)
        [times removeObjectAtIndex:0];
    if ([times count] >= _maxRequests) return NO;
    [times addObject:now];
    return YES;
}
- (void)reset { [_buckets removeAllObjects]; }
@end

#pragma mark - Auto Reply

@implementation OCAutoReply
- (instancetype)init {
    if ((self = [super init])) { _rules = [[NSMutableArray alloc] init]; }
    return self;
}
- (void)dealloc { [_rules release]; [super dealloc]; }

- (void)addRule:(NSString *)pattern response:(NSString *)response {
    [self addRule:pattern response:response channelId:nil];
}
- (void)addRule:(NSString *)pattern response:(NSString *)response channelId:(NSString *)channelId {
    [_rules addObject:@{@"pattern": pattern, @"response": response,
                         @"channelId": channelId ?: [NSNull null]}];
}
- (NSString *)autoReplyForMessage:(OCChannelMessage *)message {
    for (NSDictionary *rule in _rules) {
        id chFilter = [rule objectForKey:@"channelId"];
        if (chFilter && chFilter != [NSNull null] &&
            ![chFilter isEqualToString:message.channelId]) continue;
        NSString *pattern = [rule objectForKey:@"pattern"];
        NSRange r = [message.text rangeOfString:pattern options:NSCaseInsensitiveSearch];
        if (r.location != NSNotFound) return [rule objectForKey:@"response"];
    }
    return nil;
}
@end

#pragma mark - Presence Manager

@interface OCPresenceManager () {
    NSMutableDictionary *_users; /* "channelId:userId" -> {name, channel, since} */
}
@end

@implementation OCPresenceManager
- (instancetype)init {
    if ((self = [super init])) { _users = [[NSMutableDictionary alloc] init]; }
    return self;
}
- (void)dealloc { [_users release]; [super dealloc]; }

- (void)setOnline:(NSString *)userId channel:(NSString *)channelId name:(NSString *)name {
    NSString *key = [NSString stringWithFormat:@"%@:%@", channelId, userId];
    [_users setObject:@{@"userId": userId, @"channel": channelId,
                         @"name": name ?: userId,
                         @"since": [NSDate date]} forKey:key];
}
- (void)setOffline:(NSString *)userId channel:(NSString *)channelId {
    [_users removeObjectForKey:[NSString stringWithFormat:@"%@:%@", channelId, userId]];
}
- (NSArray *)onlineUsers { return [_users allValues]; }
- (NSArray *)onlineUsersForChannel:(NSString *)channelId {
    NSMutableArray *a = [NSMutableArray array];
    for (NSDictionary *u in [_users allValues]) {
        if ([[u objectForKey:@"channel"] isEqualToString:channelId]) [a addObject:u];
    }
    return a;
}
- (BOOL)isOnline:(NSString *)userId {
    for (NSString *key in _users) {
        if ([key hasSuffix:[NSString stringWithFormat:@":%@", userId]]) return YES;
    }
    return NO;
}
- (NSDictionary *)presenceSnapshot { return [[_users copy] autorelease]; }
@end

#pragma mark - Approval Manager

@implementation OCApprovalManager
- (instancetype)init {
    if ((self = [super init])) {
        _autoApproveReadOnly = YES;
        _trustedTools = [[NSMutableSet alloc] initWithObjects:
            @"get_datetime", @"device_info", @"calculate", @"http_fetch", nil];
    }
    return self;
}
- (void)dealloc { [_trustedTools release]; [super dealloc]; }

- (BOOL)requiresApproval:(NSString *)toolName {
    return ![_trustedTools containsObject:toolName];
}

- (void)requestApproval:(NSString *)toolName params:(NSDictionary *)params
             sessionKey:(NSString *)sessionKey completion:(void(^)(BOOL))completion {
    if (![self requiresApproval:toolName]) { completion(YES); return; }
    if (_delegate) {
        NSString *desc = [NSString stringWithFormat:@"Tool: %@\nParams: %@", toolName, params];
        [_delegate approvalManager:self requestApproval:desc forAction:toolName
                        sessionKey:sessionKey completion:completion];
    } else {
        completion(YES); /* No delegate = auto-approve */
    }
}
@end

#pragma mark - Device Pairing

@interface OCDevicePairing () {
    NSMutableArray *_paired;
    NSString *_currentCode;
    NSString *_bootstrapToken;
}
@end

@implementation OCDevicePairing
@synthesize pairedDevices = _paired;
@synthesize pairingCode = _currentCode;
@synthesize bootstrapToken = _bootstrapToken;

- (instancetype)init {
    if ((self = [super init])) {
        _paired = [[NSMutableArray alloc] init];
        _bootstrapToken = [[self _uuid] retain];
    }
    return self;
}
- (void)dealloc {
    [_paired release]; [_currentCode release]; [_bootstrapToken release];
    [super dealloc];
}

- (NSString *)generatePairingCode {
    [_currentCode release];
    _currentCode = [[NSString stringWithFormat:@"%06u", arc4random_uniform(1000000)] retain];
    return _currentCode;
}

- (NSDictionary *)generateSetupPayload:(NSString *)host port:(uint16_t)port useTLS:(BOOL)tls {
    return @{
        @"host": host ?: @"",
        @"port": @(port),
        @"tls": @(tls),
        @"bootstrapToken": _bootstrapToken ?: @"",
        @"code": _currentCode ?: @""
    };
}

- (BOOL)validatePairingCode:(NSString *)code {
    return _currentCode && [_currentCode isEqualToString:code];
}

- (void)addPairedDevice:(NSDictionary *)deviceInfo {
    [_paired addObject:deviceInfo];
}
- (void)removePairedDevice:(NSString *)deviceId {
    for (NSUInteger i = 0; i < [_paired count]; i++) {
        if ([[[_paired objectAtIndex:i] objectForKey:@"id"] isEqualToString:deviceId]) {
            [_paired removeObjectAtIndex:i]; return;
        }
    }
}

- (NSString *)_uuid {
    CFUUIDRef u = CFUUIDCreate(kCFAllocatorDefault);
    NSString *s = (NSString *)CFUUIDCreateString(kCFAllocatorDefault, u);
    CFRelease(u);
    return [s autorelease];
}
@end
