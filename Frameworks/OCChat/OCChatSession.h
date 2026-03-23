/*
 * OCChatSession.h
 * ClawPod - Chat Session & Message Framework
 *
 * Manages chat sessions, message models, streaming delta assembly,
 * and persistent storage via OCStore. Memory-efficient message
 * windowing for the 256MB device.
 */

#import <Foundation/Foundation.h>
#import "OCStore.h"
#import "OCGatewayClient.h"

#pragma mark - Message Model

typedef NS_ENUM(NSUInteger, OCMessageRole) {
    OCMessageRoleUser = 0,
    OCMessageRoleAssistant,
    OCMessageRoleSystem,
    OCMessageRoleTool
};

typedef NS_ENUM(NSUInteger, OCMessageState) {
    OCMessageStateComplete = 0,
    OCMessageStateStreaming,
    OCMessageStateAborted,
    OCMessageStateError
};

@interface OCMessage : NSObject <NSCoding>

@property (nonatomic, copy) NSString *messageId;
@property (nonatomic, assign) OCMessageRole role;
@property (nonatomic, assign) OCMessageState state;
@property (nonatomic, copy) NSString *content;
@property (nonatomic, copy) NSString *thinking;
@property (nonatomic, copy) NSDate *timestamp;
@property (nonatomic, assign) NSUInteger inputTokens;
@property (nonatomic, assign) NSUInteger outputTokens;
@property (nonatomic, copy) NSString *stopReason;
@property (nonatomic, copy) NSString *runId;

/* Streaming assembly */
@property (nonatomic, readonly) NSMutableString *streamBuffer;

- (void)appendDelta:(NSString *)delta;
- (void)finalizeStream;

/* Approximate memory cost for cache budgeting. */
- (NSUInteger)estimatedMemoryCost;

/* Convenience */
+ (OCMessage *)userMessage:(NSString *)content;
+ (OCMessage *)systemMessage:(NSString *)content;

@end

#pragma mark - Attachment Model

@interface OCAttachment : NSObject <NSCoding>
@property (nonatomic, copy) NSString *type;       // "image", "audio", "file"
@property (nonatomic, copy) NSString *mimeType;
@property (nonatomic, copy) NSString *fileName;
@property (nonatomic, copy) NSData *data;          // nil if only URL
@property (nonatomic, copy) NSString *url;
@property (nonatomic, assign) NSUInteger sizeBytes;
@end

#pragma mark - Session Model

@interface OCChatSession : NSObject <NSCoding>

@property (nonatomic, copy) NSString *sessionKey;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSDate *createdAt;
@property (nonatomic, copy) NSDate *lastActiveAt;
@property (nonatomic, assign) NSUInteger totalMessages;
@property (nonatomic, assign) BOOL isActive;

/* In-memory message window. Only keeps last N messages loaded. */
@property (nonatomic, readonly) NSArray *messages;
@property (nonatomic, assign) NSUInteger messageWindowSize;  // Default 50

@end

#pragma mark - Session Manager

@protocol OCSessionManagerDelegate <NSObject>
- (void)sessionManager:(id)manager didUpdateSession:(OCChatSession *)session;
- (void)sessionManager:(id)manager didReceiveMessage:(OCMessage *)message
             inSession:(OCChatSession *)session;
- (void)sessionManager:(id)manager didUpdateStreamingMessage:(OCMessage *)message
             inSession:(OCChatSession *)session;
@end

@interface OCSessionManager : NSObject

@property (nonatomic, assign) id<OCSessionManagerDelegate> delegate;
@property (nonatomic, readonly) NSArray *sessions;
@property (nonatomic, readonly) OCChatSession *activeSession;

- (instancetype)initWithStore:(OCStore *)store
                gatewayClient:(OCGatewayClient *)gateway;

/* Database setup */
- (BOOL)setupSchema:(NSError **)error;

/* Session operations */
- (void)loadSessions;
- (void)createSession:(NSString *)displayName;
- (void)switchToSession:(NSString *)sessionKey;
- (void)deleteSession:(NSString *)sessionKey;
- (void)resetSession:(NSString *)sessionKey;

/* Message operations */
- (void)sendMessage:(NSString *)text;
- (void)sendMessage:(NSString *)text withAttachments:(NSArray *)attachments;
- (void)abortCurrentResponse;

/* History */
- (void)loadMoreHistory;

/* Handle gateway chat events */
- (void)handleChatEvent:(OCGatewayChatEvent *)event;

/* Persistence */
- (void)persistMessage:(OCMessage *)message sessionKey:(NSString *)sessionKey;
- (NSArray *)loadMessages:(NSString *)sessionKey limit:(NSUInteger)limit offset:(NSUInteger)offset;

/* Memory management - called on memory pressure */
- (void)trimMessageWindows;
- (NSUInteger)estimatedMemoryUsage;

@end
