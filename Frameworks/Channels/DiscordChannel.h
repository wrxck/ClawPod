/*
 * OCDiscordChannel.h
 * ClawPod - Discord Bot Channel
 *
 * Connects via Discord Gateway WebSocket + REST API for sending.
 * Supports: text messages, replies, typing, guilds, threads.
 */

#import <Foundation/Foundation.h>
#import "ChannelManager.h"
#import "WebSocket.h"

@interface OCDiscordChannel : NSObject <OCChannel, OCWebSocketDelegate>
@property (nonatomic, copy) NSString *botToken;
@property (nonatomic, retain) NSArray *allowedGuildIds;
@property (nonatomic, assign) id<OCChannelManagerDelegate> messageDelegate;
- (instancetype)initWithBotToken:(NSString *)token;
@end
