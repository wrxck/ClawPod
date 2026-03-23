/*
 * OCGatewayServer.h
 * ClawPod - Native Gateway Server
 *
 * Complete ClawPod gateway running natively on iPod Touch 4.
 * Handles: WebSocket protocol v3, session management, agent execution,
 * event broadcasting, HTTP endpoints, authentication, cron, channels.
 *
 * Inspired by PicoClaw's <10MB single-binary approach.
 */

#import <Foundation/Foundation.h>
#import "OCHTTPServer.h"
#import "OCWebSocket.h"
#import "OCStore.h"
#import "OCAgent.h"
#import "OCMemoryPool.h"

#pragma mark - Gateway Configuration

@interface OCGatewayConfig : NSObject
@property (nonatomic, assign) uint16_t port;             // Default 18789
@property (nonatomic, copy) NSString *bindAddress;       // Default 0.0.0.0
@property (nonatomic, copy) NSString *authMode;          // "none", "token", "password"
@property (nonatomic, copy) NSString *authToken;
@property (nonatomic, copy) NSString *authPassword;
@property (nonatomic, copy) NSString *dataDirectory;     // Session/config storage
@property (nonatomic, assign) NSUInteger maxConnections;  // Default 8
@property (nonatomic, assign) NSTimeInterval tickInterval; // Default 30s

/* Agent config */
@property (nonatomic, copy) NSString *defaultModelId;
@property (nonatomic, copy) NSString *defaultApiKey;
@property (nonatomic, copy) NSString *defaultBaseURL;

/* Telegram channel (optional) */
@property (nonatomic, copy) NSString *telegramBotToken;
@property (nonatomic, copy) NSArray *telegramAllowedChatIds;
@end

#pragma mark - Connected Client

@interface OCGatewayWSClient : NSObject
@property (nonatomic, copy) NSString *connectionId;
@property (nonatomic, copy) NSString *clientId;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *platform;
@property (nonatomic, copy) NSString *role;          // "operator", "node"
@property (nonatomic, copy) NSArray *scopes;
@property (nonatomic, assign) BOOL authenticated;
@property (nonatomic, retain) NSDate *connectedAt;
@property (nonatomic, retain) NSOutputStream *outputStream;
@property (nonatomic, retain) NSInputStream *inputStream;
@property (nonatomic, retain) OCWebSocket *webSocket;

/* Subscriptions */
@property (nonatomic, retain) NSMutableSet *subscribedSessions;

- (void)sendJSON:(NSDictionary *)json;
- (void)sendEvent:(NSString *)event payload:(id)payload;
@end

#pragma mark - Session Entry

@interface OCGatewaySessionEntry : NSObject
@property (nonatomic, copy) NSString *sessionKey;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *status;        // "active", "completed"
@property (nonatomic, copy) NSString *model;
@property (nonatomic, assign) NSUInteger totalTokens;
@property (nonatomic, assign) double estimatedCostUsd;
@property (nonatomic, retain) NSDate *startedAt;
@property (nonatomic, retain) NSDate *updatedAt;
@property (nonatomic, copy) NSString *lastChannel;
@end

#pragma mark - Cron Job

@interface OCCronJob : NSObject
@property (nonatomic, copy) NSString *jobId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *schedule;      // Cron expression (5-field)
@property (nonatomic, copy) NSString *action;        // "send"
@property (nonatomic, copy) NSString *sessionKey;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, retain) NSDate *lastRunAt;
@property (nonatomic, retain) NSDate *nextRunAt;
@end

#pragma mark - Gateway Server Delegate

@class OCGatewayServer;

@protocol OCGatewayServerDelegate <NSObject>
@optional
- (void)gatewayServerDidStart:(OCGatewayServer *)server;
- (void)gatewayServerDidStop:(OCGatewayServer *)server;
- (void)gatewayServer:(OCGatewayServer *)server didAcceptClient:(OCGatewayWSClient *)client;
- (void)gatewayServer:(OCGatewayServer *)server didDisconnectClient:(OCGatewayWSClient *)client;
- (void)gatewayServer:(OCGatewayServer *)server didReceiveMessage:(NSString *)text
            inSession:(NSString *)sessionKey;
- (void)gatewayServer:(OCGatewayServer *)server didFailWithError:(NSError *)error;
@end

#pragma mark - Gateway Server

@interface OCGatewayServer : NSObject <OCHTTPServerDelegate, OCAgentDelegate>

@property (nonatomic, assign) id<OCGatewayServerDelegate> delegate;
@property (nonatomic, retain) OCGatewayConfig *config;
@property (nonatomic, readonly) BOOL isRunning;
@property (nonatomic, readonly) NSArray *connectedClients;
@property (nonatomic, readonly) NSArray *sessions;
@property (nonatomic, readonly) NSUInteger uptime;

- (instancetype)initWithConfig:(OCGatewayConfig *)config;

/* Lifecycle */
- (BOOL)start:(NSError **)error;
- (void)stop;

/* Session management */
- (OCGatewaySessionEntry *)createSession:(NSString *)displayName;
- (OCGatewaySessionEntry *)sessionForKey:(NSString *)key;
- (NSArray *)listSessions;
- (void)deleteSession:(NSString *)key;
- (void)resetSession:(NSString *)key;

/* Send message to agent in a session */
- (void)sendMessage:(NSString *)message
          sessionKey:(NSString *)sessionKey
          fromClient:(OCGatewayWSClient *)client
              runId:(NSString *)runId;

- (void)abortSession:(NSString *)sessionKey;

/* History */
- (NSArray *)historyForSession:(NSString *)sessionKey limit:(NSUInteger)limit;

/* Event broadcasting */
- (void)broadcastEvent:(NSString *)event payload:(id)payload;
- (void)broadcastEvent:(NSString *)event payload:(id)payload toSession:(NSString *)sessionKey;

/* Cron */
- (void)addCronJob:(OCCronJob *)job;
- (void)removeCronJob:(NSString *)jobId;
- (NSArray *)cronJobs;

/* Telegram channel */
- (void)startTelegramChannel;
- (void)stopTelegramChannel;

/* Health */
- (NSDictionary *)healthStatus;

@end
