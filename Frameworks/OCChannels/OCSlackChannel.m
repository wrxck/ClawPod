/*
 * OCSlackChannel.m
 * ClawPod - Slack Channel Implementation
 */

#import "OCSlackChannel.h"

static NSString *const kSlackAPI = @"https://slack.com/api";

@interface OCSlackChannel () { BOOL _running, _connected; }
@end

@implementation OCSlackChannel
@synthesize channelId = _channelId;
@synthesize isConnected = _connected;

- (instancetype)initWithBotToken:(NSString *)token {
    if ((self = [super init])) {
        _botToken = [token copy]; _channelId = @"slack";
    }
    return self;
}
- (void)dealloc { [_botToken release]; [_incomingWebhookURL release]; [super dealloc]; }
- (BOOL)isConfigured { return (_botToken && [_botToken length] > 0) || _incomingWebhookURL; }

- (void)start { _running = YES; _connected = YES; }
- (void)stop { _running = NO; _connected = NO; }

- (void)handleWebhookPayload:(NSDictionary *)payload {
    NSString *type = [payload objectForKey:@"type"];
    if ([type isEqualToString:@"url_verification"]) return; /* Challenge */

    NSDictionary *event = [payload objectForKey:@"event"];
    if (!event) return;
    NSString *eventType = [event objectForKey:@"type"];
    if (![eventType isEqualToString:@"message"]) return;
    if ([event objectForKey:@"bot_id"]) return; /* Skip bot messages */

    OCChannelMessage *msg = [[[OCChannelMessage alloc] init] autorelease];
    msg.channelId = @"slack";
    msg.chatId = [event objectForKey:@"channel"];
    msg.senderId = [event objectForKey:@"user"];
    msg.text = [event objectForKey:@"text"];
    msg.messageId = [event objectForKey:@"ts"];
    msg.threadId = [event objectForKey:@"thread_ts"];
    msg.isGroup = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        [_messageDelegate channelManager:nil didReceiveMessage:msg];
    });
}

- (void)sendMessage:(NSString *)text toChatId:(NSString *)chatId {
    [self sendMessage:text toChatId:chatId threadId:nil];
}

- (void)sendMessage:(NSString *)text toChatId:(NSString *)chatId threadId:(NSString *)threadId {
    if (_incomingWebhookURL && !chatId) {
        /* Use webhook */
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:
            [NSURL URLWithString:_incomingWebhookURL]];
        [req setHTTPMethod:@"POST"];
        [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        NSDictionary *body = @{@"text": text};
        [req setHTTPBody:[NSJSONSerialization dataWithJSONObject:body options:0 error:nil]];
        [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue]
            completionHandler:^(NSURLResponse *r, NSData *d, NSError *e) {}];
        return;
    }

    /* Use API */
    NSString *url = [NSString stringWithFormat:@"%@/chat.postMessage", kSlackAPI];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    [req setHTTPMethod:@"POST"];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", _botToken] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSMutableDictionary *body = [NSMutableDictionary dictionaryWithCapacity:3];
    [body setObject:chatId ?: @"" forKey:@"channel"];
    [body setObject:text forKey:@"text"];
    if (threadId) [body setObject:threadId forKey:@"thread_ts"];
    [req setHTTPBody:[NSJSONSerialization dataWithJSONObject:body options:0 error:nil]];
    [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue]
        completionHandler:^(NSURLResponse *r, NSData *d, NSError *e) {}];
}

- (void)sendReply:(NSString *)text toMessageId:(NSString *)mid chatId:(NSString *)chatId {
    [self sendMessage:text toChatId:chatId threadId:mid];
}

- (void)sendTypingIndicator:(NSString *)chatId { /* Slack doesn't support bot typing */ }
- (NSDictionary *)statusInfo { return @{@"hasWebhook": @(_incomingWebhookURL != nil)}; }
@end
