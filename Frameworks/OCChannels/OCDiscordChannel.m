/*
 * OCDiscordChannel.m
 * ClawPod - Discord Bot via Gateway WebSocket
 *
 * Connects to wss://gateway.discord.gg, handles IDENTIFY, HEARTBEAT,
 * MESSAGE_CREATE events. Sends via REST API.
 */

#import "OCDiscordChannel.h"

static NSString *const kDiscordGateway = @"wss://gateway.discord.gg/?v=10&encoding=json";
static NSString *const kDiscordAPI = @"https://discord.com/api/v10";

@interface OCDiscordChannel () {
    OCWebSocket *_ws;
    BOOL _running, _connected, _identified;
    NSTimer *_heartbeatTimer;
    NSInteger _lastSequence;
    NSString *_sessionId;
    NSString *_botUserId;
}
@end

@implementation OCDiscordChannel
@synthesize channelId = _channelId;
@synthesize isConnected = _connected;

- (instancetype)initWithBotToken:(NSString *)token {
    if ((self = [super init])) {
        _botToken = [token copy];
        _channelId = @"discord";
        _lastSequence = -1;
    }
    return self;
}
- (void)dealloc {
    [self stop]; [_botToken release]; [_sessionId release];
    [_botUserId release]; [_allowedGuildIds release];
    [super dealloc];
}
- (BOOL)isConfigured { return _botToken && [_botToken length] > 0; }

- (void)start {
    if (_running || ![self isConfigured]) return;
    _running = YES;
    _ws = [[OCWebSocket alloc] initWithURL:[NSURL URLWithString:kDiscordGateway]];
    _ws.delegate = self;
    [_ws open];
}

- (void)stop {
    _running = NO; _connected = NO; _identified = NO;
    [_heartbeatTimer invalidate]; _heartbeatTimer = nil;
    [_ws close]; [_ws release]; _ws = nil;
}

#pragma mark - OCWebSocketDelegate

- (void)webSocketDidOpen:(OCWebSocket *)ws { /* Wait for HELLO */ }

- (void)webSocket:(OCWebSocket *)ws didReceiveMessage:(NSString *)message {
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:
        [message dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if (!payload) return;

    NSInteger op = [[payload objectForKey:@"op"] integerValue];
    NSNumber *seq = [payload objectForKey:@"s"];
    if (seq && seq != (id)[NSNull null]) _lastSequence = [seq integerValue];

    switch (op) {
        case 10: { /* HELLO - start heartbeat + identify */
            NSDictionary *d = [payload objectForKey:@"d"];
            NSTimeInterval interval = [[d objectForKey:@"heartbeat_interval"] doubleValue] / 1000.0;
            _heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:interval target:self
                selector:@selector(_sendHeartbeat) userInfo:nil repeats:YES];
            [self _sendIdentify];
            break;
        }
        case 0: { /* DISPATCH */
            NSString *event = [payload objectForKey:@"t"];
            NSDictionary *d = [payload objectForKey:@"d"];
            if ([event isEqualToString:@"READY"]) {
                _connected = YES; _identified = YES;
                _sessionId = [[d objectForKey:@"session_id"] copy];
                NSDictionary *user = [d objectForKey:@"user"];
                _botUserId = [[[user objectForKey:@"id"] description] copy];
            } else if ([event isEqualToString:@"MESSAGE_CREATE"]) {
                [self _handleMessage:d];
            }
            break;
        }
        case 11: break; /* HEARTBEAT_ACK */
        case 7: { /* RECONNECT */
            [_ws close];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC),
                dispatch_get_main_queue(), ^{ if (_running) [self start]; });
            break;
        }
    }
}

- (void)webSocket:(OCWebSocket *)ws didCloseWithCode:(OCWSCloseCode)code
           reason:(NSString *)reason wasClean:(BOOL)wasClean {
    _connected = NO;
    [_heartbeatTimer invalidate]; _heartbeatTimer = nil;
    if (_running) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5*NSEC_PER_SEC),
            dispatch_get_main_queue(), ^{ [self start]; });
    }
}

- (void)webSocket:(OCWebSocket *)ws didFailWithError:(NSError *)error {
    _connected = NO;
    if (_running) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5*NSEC_PER_SEC),
            dispatch_get_main_queue(), ^{ [self start]; });
    }
}

#pragma mark - Protocol

- (void)_sendIdentify {
    NSDictionary *identify = @{@"op": @2, @"d": @{
        @"token": _botToken,
        @"intents": @(33281), /* GUILDS | GUILD_MESSAGES | MESSAGE_CONTENT | DM */
        @"properties": @{@"os": @"ios", @"browser": @"openclaw", @"device": @"ipod"}
    }};
    [_ws sendText:[[NSString alloc] initWithData:
        [NSJSONSerialization dataWithJSONObject:identify options:0 error:nil]
        encoding:NSUTF8StringEncoding]];
}

- (void)_sendHeartbeat {
    NSDictionary *hb = @{@"op": @1, @"d": _lastSequence >= 0 ? @(_lastSequence) : [NSNull null]};
    [_ws sendText:[[NSString alloc] initWithData:
        [NSJSONSerialization dataWithJSONObject:hb options:0 error:nil]
        encoding:NSUTF8StringEncoding]];
}

- (void)_handleMessage:(NSDictionary *)d {
    NSString *authorId = [[d objectForKey:@"author"] objectForKey:@"id"];
    if ([authorId isEqualToString:_botUserId]) return; /* Ignore own messages */

    NSString *guildId = [d objectForKey:@"guild_id"];
    if (_allowedGuildIds && guildId && ![_allowedGuildIds containsObject:guildId]) return;

    OCChannelMessage *msg = [[[OCChannelMessage alloc] init] autorelease];
    msg.channelId = @"discord";
    msg.chatId = [d objectForKey:@"channel_id"];
    msg.senderId = authorId;
    msg.senderName = [[d objectForKey:@"author"] objectForKey:@"username"];
    msg.text = [d objectForKey:@"content"];
    msg.messageId = [d objectForKey:@"id"];
    msg.isGroup = guildId != nil;
    msg.isDirect = guildId == nil;

    NSDictionary *ref = [d objectForKey:@"message_reference"];
    if (ref) msg.replyToId = [ref objectForKey:@"message_id"];

    dispatch_async(dispatch_get_main_queue(), ^{
        [_messageDelegate channelManager:nil didReceiveMessage:msg];
    });
}

#pragma mark - Sending

- (void)sendMessage:(NSString *)text toChatId:(NSString *)chatId {
    [self sendMessage:text toChatId:chatId threadId:nil];
}

- (void)sendMessage:(NSString *)text toChatId:(NSString *)chatId threadId:(NSString *)threadId {
    NSString *url = [NSString stringWithFormat:@"%@/channels/%@/messages", kDiscordAPI, chatId];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    [req setHTTPMethod:@"POST"];
    [req setValue:[NSString stringWithFormat:@"Bot %@", _botToken] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSMutableDictionary *body = [NSMutableDictionary dictionaryWithObject:text forKey:@"content"];
    [req setHTTPBody:[NSJSONSerialization dataWithJSONObject:body options:0 error:nil]];
    [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue]
        completionHandler:^(NSURLResponse *r, NSData *d, NSError *e) {}];
}

- (void)sendReply:(NSString *)text toMessageId:(NSString *)messageId chatId:(NSString *)chatId {
    NSString *url = [NSString stringWithFormat:@"%@/channels/%@/messages", kDiscordAPI, chatId];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    [req setHTTPMethod:@"POST"];
    [req setValue:[NSString stringWithFormat:@"Bot %@", _botToken] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSDictionary *body = @{@"content": text, @"message_reference": @{@"message_id": messageId}};
    [req setHTTPBody:[NSJSONSerialization dataWithJSONObject:body options:0 error:nil]];
    [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue]
        completionHandler:^(NSURLResponse *r, NSData *d, NSError *e) {}];
}

- (void)sendTypingIndicator:(NSString *)chatId {
    NSString *url = [NSString stringWithFormat:@"%@/channels/%@/typing", kDiscordAPI, chatId];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    [req setHTTPMethod:@"POST"];
    [req setValue:[NSString stringWithFormat:@"Bot %@", _botToken] forHTTPHeaderField:@"Authorization"];
    [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue]
        completionHandler:^(NSURLResponse *r, NSData *d, NSError *e) {}];
}

- (NSDictionary *)statusInfo {
    return @{@"sessionId": _sessionId ?: @"", @"botUserId": _botUserId ?: @""};
}
@end
