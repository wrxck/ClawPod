/*
 * OCTelegramChannel.h
 * ClawPod - Telegram Bot Channel
 *
 * Connects via Telegram Bot API using HTTP long-polling (getUpdates).
 * Supports: text messages, replies, typing indicators, groups, topics.
 */

#import <Foundation/Foundation.h>
#import "ChannelManager.h"

@interface OCTelegramChannel : NSObject <OCChannel>
@property (nonatomic, copy) NSString *botToken;
@property (nonatomic, retain) NSArray *allowedChatIds;  // nil = allow all
@property (nonatomic, assign) NSTimeInterval pollTimeout; // Default 30s

/* Delegate for inbound messages */
@property (nonatomic, assign) id<OCChannelManagerDelegate> messageDelegate;

- (instancetype)initWithBotToken:(NSString *)token;
@end
