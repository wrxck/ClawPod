/*
 * OCSlackChannel.h
 * LegacyPodClaw - Slack Channel (Incoming/Outgoing Webhooks + Events API)
 */
#import <Foundation/Foundation.h>
#import "ChannelManager.h"

@interface OCSlackChannel : NSObject <OCChannel>
@property (nonatomic, copy) NSString *botToken;          // xoxb-...
@property (nonatomic, copy) NSString *incomingWebhookURL; // For sending
@property (nonatomic, assign) id<OCChannelManagerDelegate> messageDelegate;
- (instancetype)initWithBotToken:(NSString *)token;
/* Process inbound webhook payload (called by HTTP server) */
- (void)handleWebhookPayload:(NSDictionary *)payload;
@end
