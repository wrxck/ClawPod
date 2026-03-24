/*
 * OCProviderRegistry.m
 * ClawPod - Multi-Provider Implementation
 *
 * All providers use the same pattern: HTTP POST to chat completion endpoint.
 * The only differences are URL, headers, and request body format.
 */

#import "ProviderRegistry.h"

#pragma mark - Base HTTP Provider (shared logic)

@interface _OCBaseProvider : NSObject {
    @public
    NSString *_providerId;
    NSString *_displayName;
    NSString *_apiKey;
    NSString *_baseURL;
    NSURLConnection *_conn;
    NSMutableData *_respData;
    NSMutableString *_sseBuf;
    OCProviderStreamBlock _onChunk;
    OCProviderCompletionBlock _onComplete;
}
- (void)_sendRequest:(NSMutableURLRequest *)req stream:(BOOL)stream
             onChunk:(OCProviderStreamBlock)onChunk completion:(OCProviderCompletionBlock)completion;
@end

@implementation _OCBaseProvider

- (void)dealloc {
    [_providerId release]; [_displayName release]; [_apiKey release];
    [_baseURL release]; [_respData release]; [_sseBuf release];
    [_onChunk release]; [_onComplete release];
    [super dealloc];
}

- (NSString *)providerId { return _providerId; }
- (NSString *)displayName { return _displayName; }
- (NSString *)apiKey { return _apiKey; }
- (void)setApiKey:(NSString *)k { [_apiKey release]; _apiKey = [k copy]; }
- (NSString *)baseURL { return _baseURL; }
- (void)setBaseURL:(NSString *)u { [_baseURL release]; _baseURL = [u copy]; }
- (BOOL)isConfigured { return _apiKey && [_apiKey length] > 0; }
- (void)cancel { [_conn cancel]; }
- (NSArray *)availableModels { return @[]; }

- (void)_sendRequest:(NSMutableURLRequest *)req stream:(BOOL)stream
             onChunk:(OCProviderStreamBlock)onChunk completion:(OCProviderCompletionBlock)completion {
    [_onChunk release]; _onChunk = [onChunk copy];
    [_onComplete release]; _onComplete = [completion copy];
    [_respData release]; _respData = [[NSMutableData alloc] initWithCapacity:4096];
    [_sseBuf release]; _sseBuf = [[NSMutableString alloc] init];

    [_conn cancel]; [_conn release];
    _conn = [[NSURLConnection alloc] initWithRequest:req delegate:self startImmediately:YES];
}

- (void)connection:(NSURLConnection *)c didReceiveData:(NSData *)data {
    if (_onChunk) {
        NSString *chunk = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        [_sseBuf appendString:chunk ?: @""];
        [chunk release];
        /* Parse SSE lines */
        NSArray *lines = [_sseBuf componentsSeparatedByString:@"\n"];
        [_sseBuf setString:[lines lastObject] ?: @""];
        for (NSUInteger i = 0; i < [lines count] - 1; i++) {
            NSString *line = [lines objectAtIndex:i];
            if ([line hasPrefix:@"data: "]) {
                NSString *json = [line substringFromIndex:6];
                if ([json isEqualToString:@"[DONE]"]) continue;
                NSDictionary *evt = [NSJSONSerialization JSONObjectWithData:
                    [json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
                if (evt) _onChunk(evt);
            }
        }
    } else {
        [_respData appendData:data];
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)c {
    if (!_onChunk && _onComplete) {
        NSDictionary *r = [NSJSONSerialization JSONObjectWithData:_respData options:0 error:nil];
        _onComplete(r, nil);
    } else if (_onComplete) {
        _onComplete(nil, nil);
    }
    [_onChunk release]; _onChunk = nil;
    [_onComplete release]; _onComplete = nil;
}

- (void)connection:(NSURLConnection *)c didFailWithError:(NSError *)error {
    if (_onComplete) _onComplete(nil, error);
    [_onChunk release]; _onChunk = nil;
    [_onComplete release]; _onComplete = nil;
}

@end

#pragma mark - Anthropic

@implementation OCAnthropicProvider
- (instancetype)initWithApiKey:(NSString *)key {
    if ((self = [super init])) {
        ((_OCBaseProvider *)self)->_providerId = [@"anthropic" retain];
        ((_OCBaseProvider *)self)->_displayName = [@"Anthropic" retain];
        ((_OCBaseProvider *)self)->_apiKey = [key copy];
        ((_OCBaseProvider *)self)->_baseURL = [@"https://api.anthropic.com" retain];
    }
    return self;
}
- (void)chatCompletion:(NSDictionary *)request onChunk:(OCProviderStreamBlock)c
            completion:(OCProviderCompletionBlock)comp {
    NSString *url = [NSString stringWithFormat:@"%@/v1/messages", self.baseURL];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]
        cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:120];
    [req setHTTPMethod:@"POST"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"2023-06-01" forHTTPHeaderField:@"anthropic-version"];
    [req setValue:self.apiKey forHTTPHeaderField:@"x-api-key"];
    if (c) [req setValue:@"text/event-stream" forHTTPHeaderField:@"Accept"];
    NSMutableDictionary *body = [request mutableCopy];
    if (c) [body setObject:@YES forKey:@"stream"];
    [req setHTTPBody:[NSJSONSerialization dataWithJSONObject:body options:0 error:nil]];
    [body release];
    [(_OCBaseProvider *)self _sendRequest:req stream:c!=nil onChunk:c completion:comp];
}
- (NSArray *)availableModels {
    return @[@"claude-sonnet-4-20250514", @"claude-haiku-4-5-20251001", @"claude-opus-4-20250514"];
}
@end

#pragma mark - OpenAI

@implementation OCOpenAIProvider
- (instancetype)initWithApiKey:(NSString *)key {
    if ((self = [super init])) {
        ((_OCBaseProvider *)self)->_providerId = [@"openai" retain];
        ((_OCBaseProvider *)self)->_displayName = [@"OpenAI" retain];
        ((_OCBaseProvider *)self)->_apiKey = [key copy];
        ((_OCBaseProvider *)self)->_baseURL = [@"https://api.openai.com" retain];
    }
    return self;
}
- (void)chatCompletion:(NSDictionary *)request onChunk:(OCProviderStreamBlock)c
            completion:(OCProviderCompletionBlock)comp {
    NSString *url = [NSString stringWithFormat:@"%@/v1/chat/completions", self.baseURL];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]
        cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:120];
    [req setHTTPMethod:@"POST"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", self.apiKey] forHTTPHeaderField:@"Authorization"];
    NSMutableDictionary *body = [request mutableCopy];
    if (c) [body setObject:@YES forKey:@"stream"];
    [req setHTTPBody:[NSJSONSerialization dataWithJSONObject:body options:0 error:nil]];
    [body release];
    [(_OCBaseProvider *)self _sendRequest:req stream:c!=nil onChunk:c completion:comp];
}
- (NSArray *)availableModels { return @[@"gpt-4o", @"gpt-4o-mini", @"gpt-4-turbo", @"o1", @"o3-mini"]; }
@end

#pragma mark - Google/Gemini

@implementation OCGoogleProvider
- (instancetype)initWithApiKey:(NSString *)key {
    if ((self = [super init])) {
        ((_OCBaseProvider *)self)->_providerId = [@"google" retain];
        ((_OCBaseProvider *)self)->_displayName = [@"Google" retain];
        ((_OCBaseProvider *)self)->_apiKey = [key copy];
        ((_OCBaseProvider *)self)->_baseURL = [@"https://generativelanguage.googleapis.com" retain];
    }
    return self;
}
- (void)chatCompletion:(NSDictionary *)request onChunk:(OCProviderStreamBlock)c
            completion:(OCProviderCompletionBlock)comp {
    NSString *model = [request objectForKey:@"model"] ?: @"gemini-2.5-flash";
    NSString *url = [NSString stringWithFormat:@"%@/v1beta/models/%@:generateContent?key=%@",
                     self.baseURL, model, self.apiKey];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]
        cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:120];
    [req setHTTPMethod:@"POST"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    /* Convert messages to Gemini format */
    NSArray *msgs = [request objectForKey:@"messages"];
    NSMutableArray *contents = [NSMutableArray array];
    for (NSDictionary *m in msgs) {
        NSString *role = [[m objectForKey:@"role"] isEqualToString:@"assistant"] ? @"model" : @"user";
        [contents addObject:@{@"role": role, @"parts": @[@{@"text": [m objectForKey:@"content"] ?: @""}]}];
    }
    NSDictionary *body = @{@"contents": contents};
    [req setHTTPBody:[NSJSONSerialization dataWithJSONObject:body options:0 error:nil]];
    [(_OCBaseProvider *)self _sendRequest:req stream:NO onChunk:nil completion:comp];
}
- (NSArray *)availableModels { return @[@"gemini-2.5-flash", @"gemini-2.5-pro", @"gemini-2.0-flash"]; }
@end

#pragma mark - Ollama

@implementation OCOllamaProvider
- (instancetype)initWithBaseURL:(NSString *)url {
    if ((self = [super init])) {
        ((_OCBaseProvider *)self)->_providerId = [@"ollama" retain];
        ((_OCBaseProvider *)self)->_displayName = [@"Ollama" retain];
        ((_OCBaseProvider *)self)->_baseURL = [url ?: @"http://localhost:11434" copy];
    }
    return self;
}
- (BOOL)isConfigured { return self.baseURL != nil; }
- (void)chatCompletion:(NSDictionary *)request onChunk:(OCProviderStreamBlock)c
            completion:(OCProviderCompletionBlock)comp {
    NSString *url = [NSString stringWithFormat:@"%@/api/chat", self.baseURL];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]
        cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:300];
    [req setHTTPMethod:@"POST"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSMutableDictionary *body = [request mutableCopy];
    [body setObject:@(!c) forKey:@"stream"]; /* Ollama streams by default */
    [req setHTTPBody:[NSJSONSerialization dataWithJSONObject:body options:0 error:nil]];
    [body release];
    [(_OCBaseProvider *)self _sendRequest:req stream:c!=nil onChunk:c completion:comp];
}
- (NSArray *)availableModels { return @[@"llama3.1", @"mistral", @"codellama", @"phi3"]; }
@end

#pragma mark - Groq, Together, OpenRouter, Mistral, Deepseek (OpenAI-compatible)

#define OPENAI_COMPAT_PROVIDER(CLASS, PID, DNAME, URL) \
@implementation CLASS \
- (instancetype)initWithApiKey:(NSString *)key { \
    if ((self = [super init])) { \
        ((_OCBaseProvider *)self)->_providerId = [@PID retain]; \
        ((_OCBaseProvider *)self)->_displayName = [@DNAME retain]; \
        ((_OCBaseProvider *)self)->_apiKey = [key copy]; \
        ((_OCBaseProvider *)self)->_baseURL = [@URL retain]; \
    } return self; \
} \
- (void)chatCompletion:(NSDictionary *)request onChunk:(OCProviderStreamBlock)c \
            completion:(OCProviderCompletionBlock)comp { \
    NSString *url = [NSString stringWithFormat:@"%@/v1/chat/completions", self.baseURL]; \
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url] \
        cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:120]; \
    [req setHTTPMethod:@"POST"]; \
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"]; \
    [req setValue:[NSString stringWithFormat:@"Bearer %@", self.apiKey] forHTTPHeaderField:@"Authorization"]; \
    NSMutableDictionary *body = [request mutableCopy]; \
    if (c) [body setObject:@YES forKey:@"stream"]; \
    [req setHTTPBody:[NSJSONSerialization dataWithJSONObject:body options:0 error:nil]]; \
    [body release]; \
    [(_OCBaseProvider *)self _sendRequest:req stream:c!=nil onChunk:c completion:comp]; \
} \
@end

OPENAI_COMPAT_PROVIDER(OCGroqProvider, "groq", "Groq", "https://api.groq.com/openai")
OPENAI_COMPAT_PROVIDER(OCTogetherProvider, "together", "Together AI", "https://api.together.xyz")
OPENAI_COMPAT_PROVIDER(OCOpenRouterProvider, "openrouter", "OpenRouter", "https://openrouter.ai/api")
OPENAI_COMPAT_PROVIDER(OCMistralProvider, "mistral", "Mistral", "https://api.mistral.ai")
OPENAI_COMPAT_PROVIDER(OCDeepseekProvider, "deepseek", "Deepseek", "https://api.deepseek.com")

#pragma mark - Custom Provider

@implementation OCCustomProvider
- (instancetype)initWithBaseURL:(NSString *)url apiKey:(NSString *)key {
    if ((self = [super init])) {
        ((_OCBaseProvider *)self)->_providerId = [@"custom" retain];
        ((_OCBaseProvider *)self)->_displayName = [@"Custom" retain];
        ((_OCBaseProvider *)self)->_apiKey = [key copy];
        ((_OCBaseProvider *)self)->_baseURL = [url copy];
    }
    return self;
}
- (void)chatCompletion:(NSDictionary *)request onChunk:(OCProviderStreamBlock)c
            completion:(OCProviderCompletionBlock)comp {
    NSString *url = [NSString stringWithFormat:@"%@/v1/chat/completions", self.baseURL];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]
        cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:120];
    [req setHTTPMethod:@"POST"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    if (self.apiKey) [req setValue:[NSString stringWithFormat:@"Bearer %@", self.apiKey]
                  forHTTPHeaderField:@"Authorization"];
    NSMutableDictionary *body = [request mutableCopy];
    if (c) [body setObject:@YES forKey:@"stream"];
    [req setHTTPBody:[NSJSONSerialization dataWithJSONObject:body options:0 error:nil]];
    [body release];
    [(_OCBaseProvider *)self _sendRequest:req stream:c!=nil onChunk:c completion:comp];
}
@end

#pragma mark - Provider Registry

@interface OCProviderRegistry () { NSMutableDictionary *_providerMap; }
@end

@implementation OCProviderRegistry
- (instancetype)init {
    if ((self = [super init])) {
        _providerMap = [[NSMutableDictionary alloc] initWithCapacity:12];
        _defaultProviderId = [@"anthropic" copy];
    }
    return self;
}
- (void)dealloc { [_providerMap release]; [_defaultProviderId release]; [super dealloc]; }

- (void)registerProvider:(id<OCModelProvider>)p { [_providerMap setObject:p forKey:[p providerId]]; }
- (void)removeProvider:(NSString *)pid { [_providerMap removeObjectForKey:pid]; }
- (id<OCModelProvider>)providerForId:(NSString *)pid { return [_providerMap objectForKey:pid]; }
- (id<OCModelProvider>)defaultProvider { return [_providerMap objectForKey:_defaultProviderId]; }
- (NSArray *)providers { return [_providerMap allValues]; }

- (id<OCModelProvider>)providerForModel:(NSString *)modelId {
    if (!modelId) return [self defaultProvider];
    /* Route by model prefix */
    if ([modelId hasPrefix:@"claude"]) return [_providerMap objectForKey:@"anthropic"];
    if ([modelId hasPrefix:@"gpt"] || [modelId hasPrefix:@"o1"] || [modelId hasPrefix:@"o3"])
        return [_providerMap objectForKey:@"openai"];
    if ([modelId hasPrefix:@"gemini"]) return [_providerMap objectForKey:@"google"];
    if ([modelId hasPrefix:@"llama"] || [modelId hasPrefix:@"mistral"] || [modelId hasPrefix:@"phi"])
        return [_providerMap objectForKey:@"ollama"] ?: [_providerMap objectForKey:@"groq"];
    if ([modelId hasPrefix:@"deepseek"]) return [_providerMap objectForKey:@"deepseek"];
    return [self defaultProvider];
}

- (void)chatCompletionWithFailover:(NSDictionary *)request models:(NSArray *)modelIds
    onChunk:(OCProviderStreamBlock)onChunk completion:(OCProviderCompletionBlock)completion {
    [self _tryModel:modelIds index:0 request:request onChunk:onChunk completion:completion];
}

- (void)_tryModel:(NSArray *)models index:(NSUInteger)idx request:(NSDictionary *)request
          onChunk:(OCProviderStreamBlock)onChunk completion:(OCProviderCompletionBlock)completion {
    if (idx >= [models count]) {
        completion(nil, [NSError errorWithDomain:@"OCProviders" code:-1
            userInfo:@{NSLocalizedDescriptionKey: @"All providers failed"}]);
        return;
    }
    NSString *modelId = [models objectAtIndex:idx];
    id<OCModelProvider> provider = [self providerForModel:modelId];
    if (!provider || ![provider isConfigured]) {
        [self _tryModel:models index:idx+1 request:request onChunk:onChunk completion:completion];
        return;
    }
    NSMutableDictionary *req = [request mutableCopy];
    [req setObject:modelId forKey:@"model"];
    [provider chatCompletion:req onChunk:onChunk completion:^(NSDictionary *resp, NSError *err) {
        if (err) {
            NSLog(@"[Providers] %@ failed: %@, trying next...", modelId, err);
            [self _tryModel:models index:idx+1 request:request onChunk:onChunk completion:completion];
        } else {
            completion(resp, nil);
        }
    }];
    [req release];
}

- (NSArray *)allAvailableModels {
    NSMutableArray *all = [NSMutableArray array];
    for (id<OCModelProvider> p in [_providerMap allValues]) {
        for (NSString *m in [p availableModels]) {
            [all addObject:@{@"model": m, @"provider": [p providerId]}];
        }
    }
    return all;
}
@end

#pragma mark - Cron Parser

@implementation OCCronParser

+ (BOOL)expression:(NSString *)expr matchesDate:(NSDate *)date {
    NSArray *fields = [expr componentsSeparatedByString:@" "];
    if ([fields count] != 5) return NO;

    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *c = [cal components:
        NSMinuteCalendarUnit|NSHourCalendarUnit|NSDayCalendarUnit|
        NSMonthCalendarUnit|NSWeekdayCalendarUnit fromDate:date];

    return [self _field:[fields objectAtIndex:0] matches:(int)[c minute] max:59] &&
           [self _field:[fields objectAtIndex:1] matches:(int)[c hour] max:23] &&
           [self _field:[fields objectAtIndex:2] matches:(int)[c day] max:31] &&
           [self _field:[fields objectAtIndex:3] matches:(int)[c month] max:12] &&
           [self _field:[fields objectAtIndex:4] matches:(int)([c weekday]-1) max:6];
}

+ (BOOL)_field:(NSString *)field matches:(int)value max:(int)max {
    if ([field isEqualToString:@"*"]) return YES;
    /* Step: */
    if ([field rangeOfString:@"/"].location != NSNotFound) {
        NSArray *parts = [field componentsSeparatedByString:@"/"];
        int step = [[parts objectAtIndex:1] intValue];
        if (step <= 0) return NO;
        NSString *base = [parts objectAtIndex:0];
        int start = [base isEqualToString:@"*"] ? 0 : [base intValue];
        return (value - start) % step == 0 && value >= start;
    }
    /* Range: 1-5 */
    if ([field rangeOfString:@"-"].location != NSNotFound) {
        NSArray *parts = [field componentsSeparatedByString:@"-"];
        int lo = [[parts objectAtIndex:0] intValue];
        int hi = [[parts objectAtIndex:1] intValue];
        return value >= lo && value <= hi;
    }
    /* List: 1,3,5 */
    if ([field rangeOfString:@","].location != NSNotFound) {
        for (NSString *v in [field componentsSeparatedByString:@","]) {
            if ([v intValue] == value) return YES;
        }
        return NO;
    }
    /* Exact */
    return [field intValue] == value;
}

+ (NSDate *)nextFireDate:(NSString *)expr afterDate:(NSDate *)date {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDate *check = [cal dateByAddingUnit:NSMinuteCalendarUnit value:1 toDate:date options:0];
    /* Check up to 366 days ahead */
    for (int i = 0; i < 527040; i++) { /* 366*24*60 */
        if ([self expression:expr matchesDate:check]) return check;
        check = [cal dateByAddingUnit:NSMinuteCalendarUnit value:1 toDate:check options:0];
    }
    return nil;
}

+ (BOOL)isValidExpression:(NSString *)expr {
    return [[expr componentsSeparatedByString:@" "] count] == 5;
}

@end

#pragma mark - Markdown Processor

@implementation OCMarkdownProcessor

+ (NSString *)stripMarkdown:(NSString *)md {
    if (!md) return @"";
    NSMutableString *r = [md mutableCopy];
    /* Bold **text** or __text__ */
    [r replaceOccurrencesOfString:@"**" withString:@"" options:0 range:NSMakeRange(0,[r length])];
    [r replaceOccurrencesOfString:@"__" withString:@"" options:0 range:NSMakeRange(0,[r length])];
    /* Italic *text* or _text_ - simple approach */
    /* Code `text` */
    [r replaceOccurrencesOfString:@"```" withString:@"" options:0 range:NSMakeRange(0,[r length])];
    [r replaceOccurrencesOfString:@"`" withString:@"" options:0 range:NSMakeRange(0,[r length])];
    /* Headers # */
    while ([r hasPrefix:@"#"]) [r deleteCharactersInRange:NSMakeRange(0,1)];
    return [r autorelease];
}

+ (NSString *)markdownToHTML:(NSString *)md {
    if (!md) return @"";
    NSMutableString *r = [md mutableCopy];
    /* Code blocks */
    [r replaceOccurrencesOfString:@"```" withString:@"<pre>" options:0 range:NSMakeRange(0,[r length])];
    /* Bold */
    /* Simple regex-free approach: replace pairs */
    [self _replacePairs:r marker:@"**" openTag:@"<b>" closeTag:@"</b>"];
    [self _replacePairs:r marker:@"*" openTag:@"<i>" closeTag:@"</i>"];
    [self _replacePairs:r marker:@"`" openTag:@"<code>" closeTag:@"</code>"];
    /* Line breaks */
    [r replaceOccurrencesOfString:@"\n" withString:@"<br>" options:0 range:NSMakeRange(0,[r length])];
    return [r autorelease];
}

+ (NSString *)markdownToTelegram:(NSString *)md { return md; /* Telegram supports markdown natively */ }

+ (NSString *)markdownToIRC:(NSString *)md {
    if (!md) return @"";
    NSMutableString *r = [md mutableCopy];
    [self _replacePairs:r marker:@"**" openTag:@"\x02" closeTag:@"\x02"]; /* Bold */
    [self _replacePairs:r marker:@"*" openTag:@"\x1D" closeTag:@"\x1D"]; /* Italic */
    [self _replacePairs:r marker:@"`" openTag:@"\x11" closeTag:@"\x11"]; /* Monospace */
    return [r autorelease];
}

+ (void)_replacePairs:(NSMutableString *)s marker:(NSString *)m openTag:(NSString *)o closeTag:(NSString *)c {
    BOOL open = YES;
    NSRange search = NSMakeRange(0, [s length]);
    while (search.location < [s length]) {
        NSRange found = [s rangeOfString:m options:0 range:search];
        if (found.location == NSNotFound) break;
        [s replaceCharactersInRange:found withString:open ? o : c];
        open = !open;
        search = NSMakeRange(found.location + (open ? [c length] : [o length]),
                             [s length] - found.location - (open ? [c length] : [o length]));
    }
}

@end
