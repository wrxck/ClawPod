/*
 * OCChannelManager.h
 * LegacyPodClaw - Channel System
 *
 * Manages all messaging channels (Telegram, Discord, IRC, Slack, Webhooks).
 * Routes inbound messages to sessions, outbound responses to channels.
 * Mirrors the full openclaw channel plugin architecture.
 */

#import <Foundation/Foundation.h>

#pragma mark - Channel Message

@interface OCChannelMessage : NSObject
@property (nonatomic, copy) NSString *channelId;      // "telegram", "discord", etc.
@property (nonatomic, copy) NSString *accountId;       // Bot account ID
@property (nonatomic, copy) NSString *chatId;          // Chat/channel/room ID
@property (nonatomic, copy) NSString *threadId;        // Thread/topic ID (optional)
@property (nonatomic, copy) NSString *senderId;        // Who sent this
@property (nonatomic, copy) NSString *senderName;      // Display name
@property (nonatomic, copy) NSString *text;            // Message text
@property (nonatomic, copy) NSString *replyToId;       // ID of message being replied to
@property (nonatomic, retain) NSArray *attachmentURLs;  // Media URLs
@property (nonatomic, retain) NSDate *timestamp;
@property (nonatomic, copy) NSString *messageId;       // Platform message ID
@property (nonatomic, assign) BOOL isGroup;
@property (nonatomic, assign) BOOL isDirect;
@end

#pragma mark - Channel Protocol

@protocol OCChannel <NSObject>
@required
@property (nonatomic, readonly) NSString *channelId;
@property (nonatomic, readonly) BOOL isConnected;
@property (nonatomic, readonly) BOOL isConfigured;

- (void)start;
- (void)stop;
- (void)sendMessage:(NSString *)text toChatId:(NSString *)chatId;
- (void)sendMessage:(NSString *)text toChatId:(NSString *)chatId threadId:(NSString *)threadId;
- (void)sendReply:(NSString *)text toMessageId:(NSString *)messageId chatId:(NSString *)chatId;

@optional
- (void)sendTypingIndicator:(NSString *)chatId;
- (void)sendReaction:(NSString *)emoji toMessageId:(NSString *)messageId chatId:(NSString *)chatId;
- (void)editMessage:(NSString *)messageId chatId:(NSString *)chatId newText:(NSString *)text;
- (void)deleteMessage:(NSString *)messageId chatId:(NSString *)chatId;
- (NSDictionary *)statusInfo;
@end

#pragma mark - Channel Manager Delegate

@protocol OCChannelManagerDelegate <NSObject>
- (void)channelManager:(id)manager didReceiveMessage:(OCChannelMessage *)message;
- (void)channelManager:(id)manager channel:(NSString *)channelId didChangeStatus:(BOOL)connected;
- (void)channelManager:(id)manager channel:(NSString *)channelId didFailWithError:(NSError *)error;
@end

#pragma mark - Session Router

@interface OCSessionRouter : NSObject
/* Resolve a channel message to a session key */
+ (NSString *)sessionKeyForMessage:(OCChannelMessage *)message agentId:(NSString *)agentId;
/* Build delivery context from channel message */
+ (NSDictionary *)deliveryContextForMessage:(OCChannelMessage *)message;
@end

#pragma mark - Channel Manager

@interface OCChannelManager : NSObject

@property (nonatomic, assign) id<OCChannelManagerDelegate> delegate;
@property (nonatomic, readonly) NSArray *channels;
@property (nonatomic, readonly) NSArray *connectedChannels;

- (void)registerChannel:(id<OCChannel>)channel;
- (void)removeChannel:(NSString *)channelId;
- (id<OCChannel>)channelForId:(NSString *)channelId;

- (void)startAll;
- (void)stopAll;
- (void)startChannel:(NSString *)channelId;
- (void)stopChannel:(NSString *)channelId;

/* Send outbound message to a specific channel */
- (void)sendMessage:(NSString *)text
          channelId:(NSString *)channelId
             chatId:(NSString *)chatId
           threadId:(NSString *)threadId;

/* Broadcast to all channels (for announcements) */
- (void)broadcastMessage:(NSString *)text;

/* Status */
- (NSDictionary *)allChannelStatus;

@end

#pragma mark - Rate Limiter

@interface OCRateLimiter : NSObject
- (instancetype)initWithMaxRequests:(NSUInteger)max perSeconds:(NSTimeInterval)window;
- (BOOL)allowRequestFromIP:(NSString *)ip;
- (void)reset;
@end

#pragma mark - Auto Reply

@interface OCAutoReply : NSObject
@property (nonatomic, retain) NSMutableArray *rules; /* Array of {pattern, response, channelId?} */
- (NSString *)autoReplyForMessage:(OCChannelMessage *)message;
- (void)addRule:(NSString *)pattern response:(NSString *)response;
- (void)addRule:(NSString *)pattern response:(NSString *)response channelId:(NSString *)channelId;
@end

#pragma mark - Presence Manager

@interface OCPresenceManager : NSObject
- (void)setOnline:(NSString *)userId channel:(NSString *)channelId name:(NSString *)name;
- (void)setOffline:(NSString *)userId channel:(NSString *)channelId;
- (NSArray *)onlineUsers;
- (NSArray *)onlineUsersForChannel:(NSString *)channelId;
- (BOOL)isOnline:(NSString *)userId;
- (NSDictionary *)presenceSnapshot;
@end

#pragma mark - Approval Manager

@protocol OCApprovalDelegate <NSObject>
- (void)approvalManager:(id)manager requestApproval:(NSString *)description
              forAction:(NSString *)action sessionKey:(NSString *)sessionKey
             completion:(void(^)(BOOL approved))completion;
@end

@interface OCApprovalManager : NSObject
@property (nonatomic, assign) id<OCApprovalDelegate> delegate;
@property (nonatomic, assign) BOOL autoApproveReadOnly;   // Default YES
@property (nonatomic, retain) NSMutableSet *trustedTools;  // Tools that don't need approval

- (void)requestApproval:(NSString *)toolName
                 params:(NSDictionary *)params
             sessionKey:(NSString *)sessionKey
             completion:(void(^)(BOOL approved))completion;
- (BOOL)requiresApproval:(NSString *)toolName;
@end

#pragma mark - Device Pairing

@interface OCDevicePairing : NSObject
@property (nonatomic, readonly) NSString *pairingCode;     // 6-digit code
@property (nonatomic, readonly) NSString *bootstrapToken;
@property (nonatomic, readonly) NSArray *pairedDevices;

- (NSString *)generatePairingCode;
- (NSDictionary *)generateSetupPayload:(NSString *)host port:(uint16_t)port useTLS:(BOOL)tls;
- (BOOL)validatePairingCode:(NSString *)code;
- (void)addPairedDevice:(NSDictionary *)deviceInfo;
- (void)removePairedDevice:(NSString *)deviceId;
@end
