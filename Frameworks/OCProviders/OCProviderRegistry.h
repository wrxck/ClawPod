/*
 * OCProviderRegistry.h
 * ClawPod - Multi-Provider AI Model Registry
 *
 * Supports: Anthropic, OpenAI, Google/Gemini, Ollama, Groq,
 * Together AI, OpenRouter, Mistral, Deepseek, and custom endpoints.
 * Handles failover, rotation, and model catalog.
 */

#import <Foundation/Foundation.h>

#pragma mark - Provider Protocol

typedef void(^OCProviderStreamBlock)(NSDictionary *chunk);
typedef void(^OCProviderCompletionBlock)(NSDictionary *response, NSError *error);

@protocol OCModelProvider <NSObject>
@required
@property (nonatomic, readonly) NSString *providerId;
@property (nonatomic, readonly) NSString *displayName;
@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, copy) NSString *baseURL;
@property (nonatomic, readonly) BOOL isConfigured;

- (void)chatCompletion:(NSDictionary *)request
              onChunk:(OCProviderStreamBlock)onChunk
           completion:(OCProviderCompletionBlock)completion;

- (void)cancel;
- (NSArray *)availableModels;
@end

#pragma mark - Built-in Providers

@interface OCAnthropicProvider : NSObject <OCModelProvider>
- (instancetype)initWithApiKey:(NSString *)key;
@end

@interface OCOpenAIProvider : NSObject <OCModelProvider>
- (instancetype)initWithApiKey:(NSString *)key;
@end

@interface OCGoogleProvider : NSObject <OCModelProvider>
- (instancetype)initWithApiKey:(NSString *)key;
@end

@interface OCOllamaProvider : NSObject <OCModelProvider>
- (instancetype)initWithBaseURL:(NSString *)url;
@end

@interface OCGroqProvider : NSObject <OCModelProvider>
- (instancetype)initWithApiKey:(NSString *)key;
@end

@interface OCTogetherProvider : NSObject <OCModelProvider>
- (instancetype)initWithApiKey:(NSString *)key;
@end

@interface OCOpenRouterProvider : NSObject <OCModelProvider>
- (instancetype)initWithApiKey:(NSString *)key;
@end

@interface OCMistralProvider : NSObject <OCModelProvider>
- (instancetype)initWithApiKey:(NSString *)key;
@end

@interface OCDeepseekProvider : NSObject <OCModelProvider>
- (instancetype)initWithApiKey:(NSString *)key;
@end

@interface OCCustomProvider : NSObject <OCModelProvider>
- (instancetype)initWithBaseURL:(NSString *)url apiKey:(NSString *)key;
@end

#pragma mark - Provider Registry

@interface OCProviderRegistry : NSObject

@property (nonatomic, readonly) NSArray *providers;
@property (nonatomic, copy) NSString *defaultProviderId;

- (void)registerProvider:(id<OCModelProvider>)provider;
- (void)removeProvider:(NSString *)providerId;
- (id<OCModelProvider>)providerForId:(NSString *)providerId;
- (id<OCModelProvider>)defaultProvider;

/* Model routing - find best provider for a model ID */
- (id<OCModelProvider>)providerForModel:(NSString *)modelId;

/* Failover: try providers in order until one succeeds */
- (void)chatCompletionWithFailover:(NSDictionary *)request
                           models:(NSArray *)modelIds
                          onChunk:(OCProviderStreamBlock)onChunk
                       completion:(OCProviderCompletionBlock)completion;

/* List all available models across all providers */
- (NSArray *)allAvailableModels;

@end

#pragma mark - Cron Parser

@interface OCCronParser : NSObject
/* Parse 5-field cron expression and check if it matches a date */
+ (BOOL)expression:(NSString *)expr matchesDate:(NSDate *)date;
/* Calculate next fire date from a cron expression */
+ (NSDate *)nextFireDate:(NSString *)expr afterDate:(NSDate *)date;
/* Validate cron expression */
+ (BOOL)isValidExpression:(NSString *)expr;
@end

#pragma mark - Markdown Processor

@interface OCMarkdownProcessor : NSObject
/* Convert markdown to plain text (strip formatting) */
+ (NSString *)stripMarkdown:(NSString *)markdown;
/* Convert markdown to HTML */
+ (NSString *)markdownToHTML:(NSString *)markdown;
/* Convert markdown to Telegram-compatible formatting */
+ (NSString *)markdownToTelegram:(NSString *)markdown;
/* Convert markdown to IRC formatting (bold, italic, etc.) */
+ (NSString *)markdownToIRC:(NSString *)markdown;
@end
