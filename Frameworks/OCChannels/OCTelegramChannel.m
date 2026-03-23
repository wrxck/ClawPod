/*
 * OCTelegramChannel.m
 * ClawPod - Telegram Bot API Implementation
 *
 * Long-polling via getUpdates, message sending via sendMessage.
 * Uses NSURLConnection (iOS 6 compatible).
 */

#import "OCTelegramChannel.h"

static NSString *const kTelegramAPI = @"https://api.telegram.org/bot";

@interface OCTelegramChannel () {
    BOOL _running;
    BOOL _connected;
    NSInteger _lastUpdateId;
    NSURLConnection *_pollConnection;
    NSMutableData *_pollData;
}
@end

@implementation OCTelegramChannel

@synthesize channelId = _channelId;
@synthesize isConnected = _connected;

- (instancetype)initWithBotToken:(NSString *)token {
    if ((self = [super init])) {
        _botToken = [token copy];
        _channelId = @"telegram";
        _pollTimeout = 30.0;
        _lastUpdateId = 0;
    }
    return self;
}

- (void)dealloc {
    [self stop];
    [_botToken release]; [_pollData release]; [_allowedChatIds release];
    [super dealloc];
}

- (BOOL)isConfigured { return _botToken && [_botToken length] > 0; }

#pragma mark - Lifecycle

- (void)start {
    if (_running || ![self isConfigured]) return;
    _running = YES;
    _connected = YES;
    NSLog(@"[Telegram] Starting bot polling...");
    [self _poll];
}

- (void)stop {
    _running = NO;
    _connected = NO;
    [_pollConnection cancel];
    [_pollConnection release]; _pollConnection = nil;
}

#pragma mark - Polling

- (void)_poll {
    if (!_running) return;

    NSString *url = [NSString stringWithFormat:
        @"%@%@/getUpdates?timeout=%d&offset=%ld",
        kTelegramAPI, _botToken, (int)_pollTimeout, (long)(_lastUpdateId + 1)];

    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:url]
                                         cachePolicy:NSURLRequestReloadIgnoringCacheData
                                     timeoutInterval:_pollTimeout + 10];

    [_pollData release];
    _pollData = [[NSMutableData alloc] initWithCapacity:4096];
    [_pollConnection release];
    _pollConnection = [[NSURLConnection alloc] initWithRequest:req delegate:self startImmediately:YES];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [_pollData appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    NSDictionary *resp = [NSJSONSerialization JSONObjectWithData:_pollData options:0 error:nil];
    NSArray *updates = [resp objectForKey:@"result"];

    for (NSDictionary *update in updates) {
        NSInteger updateId = [[update objectForKey:@"update_id"] integerValue];
        if (updateId > _lastUpdateId) _lastUpdateId = updateId;

        NSDictionary *msg = [update objectForKey:@"message"];
        if (!msg) continue;

        [self _processMessage:msg];
    }

    /* Continue polling */
    if (_running) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{ [self _poll]; });
    }
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    NSLog(@"[Telegram] Poll error: %@", error);
    if (_running) {
        /* Retry after backoff */
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{ [self _poll]; });
    }
}

#pragma mark - Message Processing

- (void)_processMessage:(NSDictionary *)msg {
    NSDictionary *chat = [msg objectForKey:@"chat"];
    NSString *chatId = [[chat objectForKey:@"id"] stringValue];
    NSString *chatType = [chat objectForKey:@"type"]; /* private, group, supergroup */

    /* Check allowlist */
    if (_allowedChatIds && ![_allowedChatIds containsObject:chatId]) return;

    NSDictionary *from = [msg objectForKey:@"from"];
    NSString *text = [msg objectForKey:@"text"];
    if (!text) return; /* Skip non-text for now */

    OCChannelMessage *cmsg = [[[OCChannelMessage alloc] init] autorelease];
    cmsg.channelId = @"telegram";
    cmsg.chatId = chatId;
    cmsg.senderId = [[from objectForKey:@"id"] stringValue];
    cmsg.senderName = [from objectForKey:@"first_name"] ?: [from objectForKey:@"username"];
    cmsg.text = text;
    cmsg.messageId = [[msg objectForKey:@"message_id"] stringValue];
    cmsg.isGroup = ![chatType isEqualToString:@"private"];
    cmsg.isDirect = [chatType isEqualToString:@"private"];

    /* Thread/topic support */
    NSNumber *threadId = [msg objectForKey:@"message_thread_id"];
    if (threadId) cmsg.threadId = [threadId stringValue];

    /* Reply context */
    NSDictionary *reply = [msg objectForKey:@"reply_to_message"];
    if (reply) cmsg.replyToId = [[reply objectForKey:@"message_id"] stringValue];

    dispatch_async(dispatch_get_main_queue(), ^{
        [_messageDelegate channelManager:nil didReceiveMessage:cmsg];
    });
}

#pragma mark - Sending

- (void)sendMessage:(NSString *)text toChatId:(NSString *)chatId {
    [self sendMessage:text toChatId:chatId threadId:nil];
}

- (void)sendMessage:(NSString *)text toChatId:(NSString *)chatId threadId:(NSString *)threadId {
    if (!chatId || !text) return;

    NSMutableDictionary *body = [NSMutableDictionary dictionaryWithCapacity:4];
    [body setObject:chatId forKey:@"chat_id"];
    [body setObject:text forKey:@"text"];
    [body setObject:@"Markdown" forKey:@"parse_mode"];
    if (threadId) [body setObject:threadId forKey:@"message_thread_id"];

    [self _apiCall:@"sendMessage" body:body];
}

- (void)sendReply:(NSString *)text toMessageId:(NSString *)messageId chatId:(NSString *)chatId {
    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    [body setObject:chatId forKey:@"chat_id"];
    [body setObject:text forKey:@"text"];
    [body setObject:messageId forKey:@"reply_to_message_id"];
    [body setObject:@"Markdown" forKey:@"parse_mode"];
    [self _apiCall:@"sendMessage" body:body];
}

- (void)sendTypingIndicator:(NSString *)chatId {
    [self _apiCall:@"sendChatAction" body:@{@"chat_id": chatId, @"action": @"typing"}];
}

- (void)editMessage:(NSString *)messageId chatId:(NSString *)chatId newText:(NSString *)text {
    [self _apiCall:@"editMessageText" body:@{
        @"chat_id": chatId, @"message_id": messageId, @"text": text
    }];
}

- (void)sendReaction:(NSString *)emoji toMessageId:(NSString *)messageId chatId:(NSString *)chatId {
    [self _apiCall:@"setMessageReaction" body:@{
        @"chat_id": chatId, @"message_id": messageId,
        @"reaction": @[@{@"type": @"emoji", @"emoji": emoji}]
    }];
}

- (void)deleteMessage:(NSString *)messageId chatId:(NSString *)chatId {
    [self _apiCall:@"deleteMessage" body:@{@"chat_id": chatId, @"message_id": messageId}];
}

- (NSDictionary *)statusInfo {
    return @{@"lastUpdateId": @(_lastUpdateId), @"polling": @(_running)};
}

#pragma mark - API Helper

- (void)_apiCall:(NSString *)method body:(NSDictionary *)body {
    NSString *url = [NSString stringWithFormat:@"%@%@/%@", kTelegramAPI, _botToken, method];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    [req setHTTPMethod:@"POST"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setHTTPBody:[NSJSONSerialization dataWithJSONObject:body options:0 error:nil]];
    [req setTimeoutInterval:15.0];

    [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *r, NSData *d, NSError *e) {
        if (e) NSLog(@"[Telegram] API %@ error: %@", method, e);
    }];
}

@end
