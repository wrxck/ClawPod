/*
 * OCWebhookChannel.m
 * ClawPod - Generic Webhook Channel Implementation
 */

#import "WebhookChannel.h"

@interface OCWebhookChannel () { BOOL _running, _connected; }
@end

@implementation OCWebhookChannel
@synthesize channelId = _channelId;
@synthesize isConnected = _connected;

- (instancetype)init {
    if ((self = [super init])) { _channelId = @"webhook"; }
    return self;
}
- (void)dealloc { [_callbackURL release]; [_secretToken release]; [super dealloc]; }
- (BOOL)isConfigured { return YES; /* Always available as HTTP endpoint */ }
- (void)start { _running = YES; _connected = YES; }
- (void)stop { _running = NO; _connected = NO; }

- (void)handleInboundWebhook:(NSDictionary *)payload {
    OCChannelMessage *msg = [[[OCChannelMessage alloc] init] autorelease];
    msg.channelId = @"webhook";
    msg.chatId = [payload objectForKey:@"chatId"] ?: @"default";
    msg.senderId = [payload objectForKey:@"senderId"] ?: @"webhook";
    msg.senderName = [payload objectForKey:@"senderName"] ?: @"Webhook";
    msg.text = [payload objectForKey:@"text"] ?: [payload objectForKey:@"message"] ?: @"";
    msg.isDirect = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        [_messageDelegate channelManager:nil didReceiveMessage:msg];
    });
}

- (void)sendMessage:(NSString *)text toChatId:(NSString *)chatId {
    [self sendMessage:text toChatId:chatId threadId:nil];
}

- (void)sendMessage:(NSString *)text toChatId:(NSString *)chatId threadId:(NSString *)tid {
    if (!_callbackURL) return;
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:_callbackURL]];
    [req setHTTPMethod:@"POST"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSDictionary *body = @{@"text": text, @"chatId": chatId ?: @"default"};
    [req setHTTPBody:[NSJSONSerialization dataWithJSONObject:body options:0 error:nil]];
    [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue]
        completionHandler:^(NSURLResponse *r, NSData *d, NSError *e) {}];
}

- (void)sendReply:(NSString *)text toMessageId:(NSString *)mid chatId:(NSString *)cid {
    [self sendMessage:text toChatId:cid];
}
@end
