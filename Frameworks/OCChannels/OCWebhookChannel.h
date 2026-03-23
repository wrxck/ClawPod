/*
 * OCWebhookChannel.h
 * ClawPod - Generic Webhook Channel
 *
 * Receives messages via HTTP POST to the gateway, sends responses
 * to a configurable callback URL.
 */
#import <Foundation/Foundation.h>
#import "OCChannelManager.h"

@interface OCWebhookChannel : NSObject <OCChannel>
@property (nonatomic, copy) NSString *callbackURL;    // Where to POST responses
@property (nonatomic, copy) NSString *secretToken;    // Verify inbound webhooks
@property (nonatomic, assign) id<OCChannelManagerDelegate> messageDelegate;

/* Called by HTTP server when POST /webhook/incoming is received */
- (void)handleInboundWebhook:(NSDictionary *)payload;
@end
