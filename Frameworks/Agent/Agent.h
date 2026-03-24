/*
 * OCAgent.h
 * ClawPod - Lightweight Local Agent Runtime
 *
 * Inspired by PicoClaw's <10MB approach. Provides:
 * - Local agent execution with tool orchestration
 * - HTTP-based model routing to remote AI APIs
 * - MCP (Model Context Protocol) client support
 * - Context management with token budgets
 * - The device can run as both a gateway client AND a lightweight node
 *
 * On the iPod Touch 4 this enables basic local intelligence
 * even when gateway connectivity is intermittent.
 */

#import <Foundation/Foundation.h>
#import "Store.h"
#import "MemoryPool.h"

#pragma mark - Model Configuration

typedef NS_ENUM(NSUInteger, OCModelProvider) {
    OCModelProviderAnthropic = 0,
    OCModelProviderOpenAI,
    OCModelProviderOllama,
    OCModelProviderCustom
};

@interface OCModelConfig : NSObject
@property (nonatomic, assign) OCModelProvider provider;
@property (nonatomic, copy) NSString *modelId;           // e.g., "claude-sonnet-4-20250514"
@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, copy) NSString *baseURL;           // Custom endpoint
@property (nonatomic, assign) NSUInteger maxTokens;      // Response token limit
@property (nonatomic, assign) NSUInteger contextWindow;  // Total context budget
@property (nonatomic, assign) float temperature;
@property (nonatomic, assign) NSTimeInterval timeout;    // Default 120s
@end

#pragma mark - Tool Definition

typedef void(^OCToolResultBlock)(id result, NSError *error);
typedef void(^OCToolHandler)(NSDictionary *params, OCToolResultBlock callback);

@interface OCToolDefinition : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *toolDescription;
@property (nonatomic, copy) NSDictionary *inputSchema;   // JSON Schema
@property (nonatomic, copy) OCToolHandler handler;
@property (nonatomic, assign) BOOL requiresConfirmation;
@property (nonatomic, assign) NSTimeInterval timeout;    // Default 30s
@end

#pragma mark - Agent Message

typedef NS_ENUM(NSUInteger, OCAgentMessageRole) {
    OCAgentRoleSystem = 0,
    OCAgentRoleUser,
    OCAgentRoleAssistant,
    OCAgentRoleTool
};

@interface OCAgentMessage : NSObject
@property (nonatomic, assign) OCAgentMessageRole role;
@property (nonatomic, copy) NSString *content;
@property (nonatomic, copy) NSString *toolName;
@property (nonatomic, copy) NSString *toolCallId;
@property (nonatomic, copy) NSDictionary *toolInput;
@property (nonatomic, copy) id toolResult;
@property (nonatomic, assign) NSUInteger estimatedTokens;
@end

#pragma mark - Agent Delegate

@class OCAgent;

@protocol OCAgentDelegate <NSObject>
@required
- (void)agent:(OCAgent *)agent didProduceText:(NSString *)text isFinal:(BOOL)isFinal;
- (void)agent:(OCAgent *)agent didFailWithError:(NSError *)error;
@optional
- (void)agent:(OCAgent *)agent willInvokeTool:(NSString *)toolName
   withParams:(NSDictionary *)params;
- (void)agent:(OCAgent *)agent didInvokeTool:(NSString *)toolName
       result:(id)result;
- (void)agent:(OCAgent *)agent didStartThinking:(NSString *)thinking;
- (void)agent:(OCAgent *)agent tokenUsage:(NSUInteger)input output:(NSUInteger)output;
@end

#pragma mark - MCP Client

/*
 * Lightweight MCP (Model Context Protocol) client for connecting
 * to local or remote tool servers.
 */
@interface OCMCPClient : NSObject

@property (nonatomic, copy) NSString *serverURL;
@property (nonatomic, copy) NSString *serverName;
@property (nonatomic, readonly) BOOL isConnected;
@property (nonatomic, readonly) NSArray *availableTools;

- (instancetype)initWithURL:(NSString *)url name:(NSString *)name;

- (void)connect:(void(^)(BOOL success, NSError *error))callback;
- (void)disconnect;

- (void)callTool:(NSString *)toolName
          params:(NSDictionary *)params
        callback:(OCToolResultBlock)callback;

- (void)listTools:(void(^)(NSArray *tools, NSError *error))callback;

@end

#pragma mark - Agent Runtime

@interface OCAgent : NSObject

@property (nonatomic, assign) id<OCAgentDelegate> delegate;
@property (nonatomic, retain) OCModelConfig *modelConfig;
@property (nonatomic, copy) NSString *systemPrompt;
@property (nonatomic, readonly) BOOL isProcessing;

/* Token budget management */
@property (nonatomic, assign) NSUInteger maxContextTokens;  // Default 4096 (conservative)
@property (nonatomic, assign) NSUInteger maxResponseTokens;  // Default 1024
@property (nonatomic, readonly) NSUInteger currentContextTokens;

/* Tool management */
- (void)registerTool:(OCToolDefinition *)tool;
- (void)removeTool:(NSString *)toolName;
- (NSArray *)registeredTools;

/* MCP server connections */
- (void)addMCPServer:(OCMCPClient *)server;
- (void)removeMCPServer:(NSString *)serverName;

/* Run agent */
- (void)processMessage:(NSString *)userMessage;
- (void)processMessage:(NSString *)userMessage withContext:(NSArray *)additionalMessages;
- (void)abort;

/* Context management */
- (void)clearContext;
- (void)addSystemMessage:(NSString *)message;
- (NSArray *)contextMessages;

/* Conversation memory - auto-compacts when over token budget */
- (void)compactContext;

/* Estimate tokens for a string (rough: chars/4) */
+ (NSUInteger)estimateTokens:(NSString *)text;

@end

#pragma mark - HTTP Model Client

/*
 * Low-level HTTP client for AI model APIs.
 * Handles streaming responses via chunked transfer encoding.
 * Uses NSURLConnection (iOS 6 compatible, not NSURLSession).
 */
@interface OCModelHTTPClient : NSObject <NSURLConnectionDataDelegate>

@property (nonatomic, copy) NSString *baseURL;
@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, assign) NSTimeInterval timeout;

- (instancetype)initWithBaseURL:(NSString *)baseURL apiKey:(NSString *)apiKey;

/* Streaming chat completion. onChunk called for each SSE data line. */
- (void)chatCompletion:(NSDictionary *)requestBody
               onChunk:(void(^)(NSDictionary *chunk))onChunk
            completion:(void(^)(NSDictionary *fullResponse, NSError *error))completion;

/* Non-streaming chat completion. */
- (void)chatCompletionSync:(NSDictionary *)requestBody
                completion:(void(^)(NSDictionary *response, NSError *error))completion;

- (void)cancel;

@end

#pragma mark - Built-in Tools

/*
 * Factory for device-local tools that can run on the iPod Touch.
 */
@interface OCBuiltinTools : NSObject

/* Returns array of OCToolDefinition for device-local tools */
+ (NSArray *)deviceTools;

/* Individual tools */
+ (OCToolDefinition *)dateTimeTool;
+ (OCToolDefinition *)deviceInfoTool;
+ (OCToolDefinition *)clipboardTool;
+ (OCToolDefinition *)httpFetchTool;
+ (OCToolDefinition *)fileReadTool;
+ (OCToolDefinition *)mathTool;
+ (OCToolDefinition *)timerTool;

@end
