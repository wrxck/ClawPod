/*
 * OCAgent.m
 * ClawPod - Lightweight Local Agent Runtime Implementation
 *
 * Inspired by PicoClaw: single-process, <10MB memory footprint.
 * Uses NSURLConnection for HTTP (iOS 6 compatible).
 * Handles streaming SSE responses for real-time output.
 */

#import "Agent.h"
#import <UIKit/UIKit.h>

static const NSUInteger kDefaultMaxContext  = 4096;
static const NSUInteger kDefaultMaxResponse = 1024;
static const NSTimeInterval kDefaultTimeout = 120.0;

#pragma mark - OCModelConfig

@implementation OCModelConfig

- (instancetype)init {
    if ((self = [super init])) {
        _maxTokens = kDefaultMaxResponse;
        _contextWindow = kDefaultMaxContext;
        _temperature = 0.7f;
        _timeout = kDefaultTimeout;
    }
    return self;
}

- (void)dealloc {
    [_modelId release]; [_apiKey release]; [_baseURL release];
    [super dealloc];
}

@end

#pragma mark - OCToolDefinition

@implementation OCToolDefinition

- (instancetype)init {
    if ((self = [super init])) {
        _timeout = 30.0;
    }
    return self;
}

- (void)dealloc {
    [_name release]; [_toolDescription release];
    [_inputSchema release]; [_handler release];
    [super dealloc];
}

@end

#pragma mark - OCAgentMessage

@implementation OCAgentMessage

- (void)dealloc {
    [_content release]; [_toolName release]; [_toolCallId release];
    [_toolInput release]; [_toolResult release];
    [super dealloc];
}

- (NSUInteger)estimatedTokens {
    if (_estimatedTokens > 0) return _estimatedTokens;
    return [OCAgent estimateTokens:_content];
}

@end

#pragma mark - OCMCPClient

@interface OCMCPClient () {
    NSMutableArray *_tools;
}
@end

@implementation OCMCPClient

@synthesize availableTools = _tools;

- (instancetype)initWithURL:(NSString *)url name:(NSString *)name {
    if ((self = [super init])) {
        _serverURL = [url copy];
        _serverName = [name copy];
        _tools = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_serverURL release]; [_serverName release]; [_tools release];
    [super dealloc];
}

- (void)connect:(void(^)(BOOL, NSError *))callback {
    /* Send initialize request to MCP server */
    NSURL *url = [NSURL URLWithString:_serverURL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSDictionary *body = @{
        @"jsonrpc": @"2.0",
        @"method": @"initialize",
        @"params": @{
            @"protocolVersion": @"2024-11-05",
            @"capabilities": @{},
            @"clientInfo": @{
                @"name": @"openclaw-ios6",
                @"version": @"0.1.0"
            }
        },
        @"id": @1
    };

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    [request setHTTPBody:jsonData];

    [NSURLConnection sendAsynchronousRequest:request
                                       queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *resp, NSData *data, NSError *error) {
        if (error) {
            callback(NO, error);
            return;
        }
        _isConnected = YES;
        /* Fetch tool list */
        [self listTools:^(NSArray *tools, NSError *err) {
            callback(err == nil, err);
        }];
    }];
}

- (void)disconnect {
    _isConnected = NO;
    [_tools removeAllObjects];
}

- (void)callTool:(NSString *)toolName
          params:(NSDictionary *)params
        callback:(OCToolResultBlock)callback {
    NSURL *url = [NSURL URLWithString:_serverURL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSDictionary *body = @{
        @"jsonrpc": @"2.0",
        @"method": @"tools/call",
        @"params": @{
            @"name": toolName,
            @"arguments": params ?: @{}
        },
        @"id": @2
    };

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    [request setHTTPBody:jsonData];

    [NSURLConnection sendAsynchronousRequest:request
                                       queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *resp, NSData *data, NSError *error) {
        if (error) { callback(nil, error); return; }

        NSDictionary *result = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSDictionary *resultPayload = [result objectForKey:@"result"];
        callback(resultPayload, nil);
    }];
}

- (void)listTools:(void(^)(NSArray *, NSError *))callback {
    NSURL *url = [NSURL URLWithString:_serverURL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSDictionary *body = @{
        @"jsonrpc": @"2.0",
        @"method": @"tools/list",
        @"params": @{},
        @"id": @3
    };

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    [request setHTTPBody:jsonData];

    [NSURLConnection sendAsynchronousRequest:request
                                       queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *resp, NSData *data, NSError *error) {
        if (error) { callback(nil, error); return; }

        NSDictionary *result = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSArray *tools = [[result objectForKey:@"result"] objectForKey:@"tools"];
        [_tools removeAllObjects];

        for (NSDictionary *t in tools) {
            OCToolDefinition *tool = [[OCToolDefinition alloc] init];
            tool.name = [t objectForKey:@"name"];
            tool.toolDescription = [t objectForKey:@"description"];
            tool.inputSchema = [t objectForKey:@"inputSchema"];
            [_tools addObject:tool];
            [tool release];
        }
        callback(_tools, nil);
    }];
}

@end

#pragma mark - OCModelHTTPClient

@interface OCModelHTTPClient () {
    NSURLConnection *_connection;
    NSMutableData *_responseData;
    NSString *_sseBuffer;
    void(^_onChunk)(NSDictionary *);
    void(^_onComplete)(NSDictionary *, NSError *);
    BOOL _isStreaming;
}
@end

@implementation OCModelHTTPClient

- (instancetype)initWithBaseURL:(NSString *)baseURL apiKey:(NSString *)apiKey {
    if ((self = [super init])) {
        _baseURL = [baseURL copy];
        _apiKey = [apiKey copy];
        _timeout = kDefaultTimeout;
    }
    return self;
}

- (void)dealloc {
    [self cancel];
    [_baseURL release]; [_apiKey release];
    [_responseData release]; [_sseBuffer release];
    [_onChunk release]; [_onComplete release];
    [super dealloc];
}

- (void)chatCompletion:(NSDictionary *)requestBody
               onChunk:(void(^)(NSDictionary *))onChunk
            completion:(void(^)(NSDictionary *, NSError *))completion {

    [_onChunk release]; _onChunk = [onChunk copy];
    [_onComplete release]; _onComplete = [completion copy];
    _isStreaming = YES;

    NSMutableDictionary *body = [requestBody mutableCopy];
    [body setObject:@YES forKey:@"stream"];

    [self _sendRequest:body];
    [body release];
}

- (void)chatCompletionSync:(NSDictionary *)requestBody
                completion:(void(^)(NSDictionary *, NSError *))completion {
    [_onComplete release]; _onComplete = [completion copy];
    _isStreaming = NO;

    [self _sendRequest:requestBody];
}

- (void)_sendRequest:(NSDictionary *)body {
    NSString *urlStr = [NSString stringWithFormat:@"%@/v1/messages", _baseURL];
    NSURL *url = [NSURL URLWithString:urlStr];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                          cachePolicy:NSURLRequestReloadIgnoringCacheData
                                                      timeoutInterval:_timeout];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"2023-06-01" forHTTPHeaderField:@"anthropic-version"];

    if (_apiKey) {
        [request setValue:_apiKey forHTTPHeaderField:@"x-api-key"];
    }

    if (_isStreaming) {
        [request setValue:@"text/event-stream" forHTTPHeaderField:@"Accept"];
    }

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    [request setHTTPBody:jsonData];

    [_responseData release];
    _responseData = [[NSMutableData alloc] initWithCapacity:4096];
    [_sseBuffer release];
    _sseBuffer = [[NSString alloc] init];

    [_connection cancel];
    _connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:YES];
}

- (void)cancel {
    [_connection cancel];
    [_connection release]; _connection = nil;
}

#pragma mark NSURLConnectionDataDelegate

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    if (_isStreaming) {
        /* Parse SSE events */
        NSString *chunk = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSString *combined = [_sseBuffer stringByAppendingString:chunk];
        [chunk release];

        NSArray *lines = [combined componentsSeparatedByString:@"\n"];
        NSMutableString *incomplete = [NSMutableString string];

        for (NSUInteger i = 0; i < [lines count]; i++) {
            NSString *line = [lines objectAtIndex:i];

            /* Last element might be incomplete */
            if (i == [lines count] - 1 && ![combined hasSuffix:@"\n"]) {
                [incomplete appendString:line];
                continue;
            }

            if ([line hasPrefix:@"data: "]) {
                NSString *jsonStr = [line substringFromIndex:6];
                if ([jsonStr isEqualToString:@"[DONE]"]) continue;

                NSData *jsonData = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];
                NSDictionary *event = [NSJSONSerialization JSONObjectWithData:jsonData
                                                                     options:0 error:nil];
                if (event && _onChunk) {
                    _onChunk(event);
                }
            }
        }

        [_sseBuffer release];
        _sseBuffer = [incomplete copy];
    } else {
        [_responseData appendData:data];
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    if (!_isStreaming && _onComplete) {
        NSDictionary *result = [NSJSONSerialization JSONObjectWithData:_responseData
                                                              options:0 error:nil];
        _onComplete(result, nil);
    } else if (_isStreaming && _onComplete) {
        _onComplete(nil, nil);
    }

    [self _cleanup];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    if (_onComplete) {
        _onComplete(nil, error);
    }
    [self _cleanup];
}

- (void)_cleanup {
    [_connection release]; _connection = nil;
    [_responseData release]; _responseData = nil;
    [_onChunk release]; _onChunk = nil;
    [_onComplete release]; _onComplete = nil;
}

@end

#pragma mark - OCAgent

@interface OCAgent () {
    NSMutableArray *_tools;
    NSMutableArray *_mcpServers;
    NSMutableArray *_contextMessages;
    OCModelHTTPClient *_httpClient;
    BOOL _aborted;
}
@end

@implementation OCAgent

- (instancetype)init {
    if ((self = [super init])) {
        _tools = [[NSMutableArray alloc] initWithCapacity:8];
        _mcpServers = [[NSMutableArray alloc] initWithCapacity:2];
        _contextMessages = [[NSMutableArray alloc] initWithCapacity:32];
        _maxContextTokens = kDefaultMaxContext;
        _maxResponseTokens = kDefaultMaxResponse;
    }
    return self;
}

- (void)dealloc {
    [_tools release]; [_mcpServers release]; [_contextMessages release];
    [_httpClient release]; [_modelConfig release]; [_systemPrompt release];
    [super dealloc];
}

#pragma mark - Tool Management

- (void)registerTool:(OCToolDefinition *)tool {
    [_tools addObject:tool];
}

- (void)removeTool:(NSString *)toolName {
    for (NSUInteger i = 0; i < [_tools count]; i++) {
        OCToolDefinition *t = [_tools objectAtIndex:i];
        if ([t.name isEqualToString:toolName]) {
            [_tools removeObjectAtIndex:i];
            return;
        }
    }
}

- (NSArray *)registeredTools {
    return [[_tools copy] autorelease];
}

- (void)addMCPServer:(OCMCPClient *)server {
    [_mcpServers addObject:server];
}

- (void)removeMCPServer:(NSString *)serverName {
    for (NSUInteger i = 0; i < [_mcpServers count]; i++) {
        OCMCPClient *s = [_mcpServers objectAtIndex:i];
        if ([s.serverName isEqualToString:serverName]) {
            [_mcpServers removeObjectAtIndex:i];
            return;
        }
    }
}

#pragma mark - Agent Loop

- (void)processMessage:(NSString *)userMessage {
    [self processMessage:userMessage withContext:nil];
}

- (void)processMessage:(NSString *)userMessage withContext:(NSArray *)additionalMessages {
    if (_isProcessing) return;
    _isProcessing = YES;
    _aborted = NO;

    /* Add user message to context */
    OCAgentMessage *userMsg = [[OCAgentMessage alloc] init];
    userMsg.role = OCAgentRoleUser;
    userMsg.content = userMessage;
    [_contextMessages addObject:userMsg];
    [userMsg release];

    if (additionalMessages) {
        [_contextMessages addObjectsFromArray:additionalMessages];
    }

    /* Compact if over budget */
    [self compactContext];

    /* Start the agent loop */
    [self _runAgentLoop];
}

- (void)_runAgentLoop {
    if (_aborted) {
        _isProcessing = NO;
        return;
    }

    /* Build API request */
    NSDictionary *requestBody = [self _buildRequestBody];

    /* Create HTTP client if needed */
    if (!_httpClient) {
        NSString *baseURL = _modelConfig.baseURL ?: @"https://api.anthropic.com";
        _httpClient = [[OCModelHTTPClient alloc] initWithBaseURL:baseURL
                                                         apiKey:_modelConfig.apiKey];
        _httpClient.timeout = _modelConfig.timeout;
    }

    __block NSMutableString *accumulated = [[NSMutableString alloc] init];
    __block NSMutableArray *toolCalls = [[NSMutableArray alloc] init];

    [_httpClient chatCompletion:requestBody
                        onChunk:^(NSDictionary *chunk) {
        if (_aborted) return;

        NSString *type = [chunk objectForKey:@"type"];

        if ([type isEqualToString:@"content_block_delta"]) {
            NSDictionary *delta = [chunk objectForKey:@"delta"];
            NSString *deltaType = [delta objectForKey:@"type"];

            if ([deltaType isEqualToString:@"text_delta"]) {
                NSString *text = [delta objectForKey:@"text"];
                if (text) {
                    [accumulated appendString:text];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [_delegate agent:self didProduceText:text isFinal:NO];
                    });
                }
            } else if ([deltaType isEqualToString:@"input_json_delta"]) {
                /* Tool use input streaming */
            }
        } else if ([type isEqualToString:@"content_block_start"]) {
            NSDictionary *block = [chunk objectForKey:@"content_block"];
            if ([[block objectForKey:@"type"] isEqualToString:@"tool_use"]) {
                [toolCalls addObject:[block mutableCopy]];
            }
        } else if ([type isEqualToString:@"message_delta"]) {
            NSDictionary *usage = [chunk objectForKey:@"usage"];
            if (usage) {
                NSUInteger input = [[usage objectForKey:@"input_tokens"] unsignedIntegerValue];
                NSUInteger output = [[usage objectForKey:@"output_tokens"] unsignedIntegerValue];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([_delegate respondsToSelector:@selector(agent:tokenUsage:output:)]) {
                        [_delegate agent:self tokenUsage:input output:output];
                    }
                });
            }
        }
    }
                     completion:^(NSDictionary *fullResponse, NSError *error) {
        if (error) {
            _isProcessing = NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                [_delegate agent:self didFailWithError:error];
            });
            [accumulated release];
            [toolCalls release];
            return;
        }

        /* Add assistant message to context */
        if ([accumulated length] > 0) {
            OCAgentMessage *assistantMsg = [[OCAgentMessage alloc] init];
            assistantMsg.role = OCAgentRoleAssistant;
            assistantMsg.content = [[accumulated copy] autorelease];
            [_contextMessages addObject:assistantMsg];
            [assistantMsg release];
        }

        /* Handle tool calls */
        if ([toolCalls count] > 0) {
            [self _executeToolCalls:toolCalls completion:^{
                /* Continue agent loop after tool execution */
                [self _runAgentLoop];
            }];
        } else {
            /* No tool calls - we're done */
            _isProcessing = NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                [_delegate agent:self didProduceText:accumulated isFinal:YES];
            });
        }

        [accumulated release];
        [toolCalls release];
    }];
}

- (void)_executeToolCalls:(NSArray *)toolCalls completion:(void(^)(void))completion {
    __block NSUInteger remaining = [toolCalls count];

    for (NSDictionary *call in toolCalls) {
        NSString *toolName = [call objectForKey:@"name"];
        NSString *toolId = [call objectForKey:@"id"];
        NSDictionary *input = [call objectForKey:@"input"] ?: @{};

        dispatch_async(dispatch_get_main_queue(), ^{
            if ([_delegate respondsToSelector:@selector(agent:willInvokeTool:withParams:)]) {
                [_delegate agent:self willInvokeTool:toolName withParams:input];
            }
        });

        /* Find handler - check local tools first, then MCP servers */
        OCToolDefinition *localTool = nil;
        for (OCToolDefinition *t in _tools) {
            if ([t.name isEqualToString:toolName]) {
                localTool = t;
                break;
            }
        }

        if (localTool && localTool.handler) {
            localTool.handler(input, ^(id result, NSError *error) {
                [self _addToolResult:result error:error toolId:toolId toolName:toolName];
                if (--remaining == 0) completion();
            });
        } else {
            /* Try MCP servers */
            BOOL found = NO;
            for (OCMCPClient *mcp in _mcpServers) {
                for (OCToolDefinition *t in mcp.availableTools) {
                    if ([t.name isEqualToString:toolName]) {
                        [mcp callTool:toolName params:input callback:^(id result, NSError *error) {
                            [self _addToolResult:result error:error toolId:toolId toolName:toolName];
                            if (--remaining == 0) completion();
                        }];
                        found = YES;
                        break;
                    }
                }
                if (found) break;
            }

            if (!found) {
                [self _addToolResult:@"Tool not found" error:nil toolId:toolId toolName:toolName];
                if (--remaining == 0) completion();
            }
        }
    }
}

- (void)_addToolResult:(id)result error:(NSError *)error
                toolId:(NSString *)toolId toolName:(NSString *)toolName {
    OCAgentMessage *toolMsg = [[OCAgentMessage alloc] init];
    toolMsg.role = OCAgentRoleTool;
    toolMsg.toolCallId = toolId;
    toolMsg.toolName = toolName;

    if (error) {
        toolMsg.toolResult = [NSString stringWithFormat:@"Error: %@",
                              [error localizedDescription]];
    } else {
        toolMsg.toolResult = result;
    }

    NSString *resultStr;
    if ([result isKindOfClass:[NSString class]]) {
        resultStr = result;
    } else {
        NSData *json = [NSJSONSerialization dataWithJSONObject:result ?: @{} options:0 error:nil];
        resultStr = [[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] autorelease];
    }
    toolMsg.content = resultStr;

    [_contextMessages addObject:toolMsg];
    [toolMsg release];

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([_delegate respondsToSelector:@selector(agent:didInvokeTool:result:)]) {
            [_delegate agent:self didInvokeTool:toolName result:result];
        }
    });
}

- (void)abort {
    _aborted = YES;
    [_httpClient cancel];
    _isProcessing = NO;
}

#pragma mark - Context Management

- (void)clearContext {
    [_contextMessages removeAllObjects];
    _currentContextTokens = 0;
}

- (void)addSystemMessage:(NSString *)message {
    OCAgentMessage *msg = [[OCAgentMessage alloc] init];
    msg.role = OCAgentRoleSystem;
    msg.content = message;
    [_contextMessages insertObject:msg atIndex:0];
    [msg release];
}

- (NSArray *)contextMessages {
    return [[_contextMessages copy] autorelease];
}

- (void)compactContext {
    /* Calculate current token usage */
    NSUInteger total = 0;
    for (OCAgentMessage *msg in _contextMessages) {
        total += [msg estimatedTokens];
    }
    _currentContextTokens = total;

    /* Remove oldest non-system messages if over budget */
    while (_currentContextTokens > _maxContextTokens && [_contextMessages count] > 2) {
        /* Find first non-system message */
        for (NSUInteger i = 0; i < [_contextMessages count]; i++) {
            OCAgentMessage *msg = [_contextMessages objectAtIndex:i];
            if (msg.role != OCAgentRoleSystem) {
                _currentContextTokens -= [msg estimatedTokens];
                [_contextMessages removeObjectAtIndex:i];
                break;
            }
        }
    }
}

#pragma mark - Request Building

- (NSDictionary *)_buildRequestBody {
    NSMutableArray *messages = [NSMutableArray arrayWithCapacity:[_contextMessages count]];

    for (OCAgentMessage *msg in _contextMessages) {
        if (msg.role == OCAgentRoleSystem) continue; /* System prompt handled separately */

        NSMutableDictionary *msgDict = [NSMutableDictionary dictionary];

        switch (msg.role) {
            case OCAgentRoleUser:
                [msgDict setObject:@"user" forKey:@"role"];
                [msgDict setObject:msg.content ?: @"" forKey:@"content"];
                break;
            case OCAgentRoleAssistant:
                [msgDict setObject:@"assistant" forKey:@"role"];
                [msgDict setObject:msg.content ?: @"" forKey:@"content"];
                break;
            case OCAgentRoleTool:
                [msgDict setObject:@"user" forKey:@"role"];
                [msgDict setObject:@[
                    @{
                        @"type": @"tool_result",
                        @"tool_use_id": msg.toolCallId ?: @"",
                        @"content": msg.content ?: @""
                    }
                ] forKey:@"content"];
                break;
            default: break;
        }

        [messages addObject:msgDict];
    }

    NSMutableDictionary *body = [NSMutableDictionary dictionaryWithCapacity:8];
    [body setObject:_modelConfig.modelId ?: @"claude-sonnet-4-20250514" forKey:@"model"];
    [body setObject:messages forKey:@"messages"];
    [body setObject:@(_modelConfig.maxTokens) forKey:@"max_tokens"];

    if (_systemPrompt) {
        [body setObject:_systemPrompt forKey:@"system"];
    }

    if (_modelConfig.temperature > 0) {
        [body setObject:@(_modelConfig.temperature) forKey:@"temperature"];
    }

    /* Add tool definitions */
    if ([_tools count] > 0 || [_mcpServers count] > 0) {
        NSMutableArray *toolDefs = [NSMutableArray array];

        for (OCToolDefinition *tool in _tools) {
            [toolDefs addObject:@{
                @"name": tool.name,
                @"description": tool.toolDescription ?: @"",
                @"input_schema": tool.inputSchema ?: @{@"type": @"object"}
            }];
        }

        for (OCMCPClient *mcp in _mcpServers) {
            for (OCToolDefinition *tool in mcp.availableTools) {
                [toolDefs addObject:@{
                    @"name": tool.name,
                    @"description": tool.toolDescription ?: @"",
                    @"input_schema": tool.inputSchema ?: @{@"type": @"object"}
                }];
            }
        }

        [body setObject:toolDefs forKey:@"tools"];
    }

    return body;
}

#pragma mark - Token Estimation

+ (NSUInteger)estimateTokens:(NSString *)text {
    if (!text) return 0;
    /* Rough estimate: ~4 characters per token for English */
    return ([text length] + 3) / 4;
}

@end

#pragma mark - OCBuiltinTools

@implementation OCBuiltinTools

+ (NSArray *)deviceTools {
    return @[
        [self dateTimeTool],
        [self deviceInfoTool],
        [self clipboardTool],
        [self httpFetchTool],
        [self mathTool],
        [self timerTool]
    ];
}

+ (OCToolDefinition *)dateTimeTool {
    OCToolDefinition *tool = [[[OCToolDefinition alloc] init] autorelease];
    tool.name = @"get_datetime";
    tool.toolDescription = @"Get the current date and time";
    tool.inputSchema = @{@"type": @"object", @"properties": @{}};
    tool.handler = ^(NSDictionary *params, OCToolResultBlock callback) {
        NSDateFormatter *fmt = [[[NSDateFormatter alloc] init] autorelease];
        [fmt setDateFormat:@"yyyy-MM-dd HH:mm:ss Z"];
        callback([fmt stringFromDate:[NSDate date]], nil);
    };
    return tool;
}

+ (OCToolDefinition *)deviceInfoTool {
    OCToolDefinition *tool = [[[OCToolDefinition alloc] init] autorelease];
    tool.name = @"device_info";
    tool.toolDescription = @"Get device information (model, OS, memory)";
    tool.inputSchema = @{@"type": @"object", @"properties": @{}};
    tool.handler = ^(NSDictionary *params, OCToolResultBlock callback) {
        OCMemoryMonitor *mon = [OCMemoryMonitor sharedMonitor];
        [mon checkNow];
        NSDictionary *info = @{
            @"device": [[UIDevice currentDevice] model],
            @"systemName": [[UIDevice currentDevice] systemName],
            @"systemVersion": [[UIDevice currentDevice] systemVersion],
            @"name": [[UIDevice currentDevice] name],
            @"freeMemoryMB": @(mon.freeMemoryBytes / (1024 * 1024)),
            @"appMemoryMB": @(mon.appMemoryBytes / (1024 * 1024))
        };
        callback(info, nil);
    };
    return tool;
}

+ (OCToolDefinition *)clipboardTool {
    OCToolDefinition *tool = [[[OCToolDefinition alloc] init] autorelease];
    tool.name = @"clipboard";
    tool.toolDescription = @"Read or write the device clipboard";
    tool.inputSchema = @{
        @"type": @"object",
        @"properties": @{
            @"action": @{@"type": @"string", @"enum": @[@"read", @"write"]},
            @"text": @{@"type": @"string"}
        },
        @"required": @[@"action"]
    };
    tool.handler = ^(NSDictionary *params, OCToolResultBlock callback) {
        NSString *action = [params objectForKey:@"action"];
        if ([action isEqualToString:@"read"]) {
            NSString *text = [[UIPasteboard generalPasteboard] string] ?: @"";
            callback(text, nil);
        } else if ([action isEqualToString:@"write"]) {
            [[UIPasteboard generalPasteboard] setString:[params objectForKey:@"text"] ?: @""];
            callback(@"Copied to clipboard", nil);
        }
    };
    return tool;
}

+ (OCToolDefinition *)httpFetchTool {
    OCToolDefinition *tool = [[[OCToolDefinition alloc] init] autorelease];
    tool.name = @"http_fetch";
    tool.toolDescription = @"Fetch content from a URL via HTTP GET";
    tool.inputSchema = @{
        @"type": @"object",
        @"properties": @{
            @"url": @{@"type": @"string"}
        },
        @"required": @[@"url"]
    };
    tool.timeout = 30.0;
    tool.handler = ^(NSDictionary *params, OCToolResultBlock callback) {
        NSString *urlStr = [params objectForKey:@"url"];
        NSURL *url = [NSURL URLWithString:urlStr];
        if (!url) { callback(@"Invalid URL", nil); return; }

        NSURLRequest *req = [NSURLRequest requestWithURL:url
                                             cachePolicy:NSURLRequestReloadIgnoringCacheData
                                         timeoutInterval:30.0];
        [NSURLConnection sendAsynchronousRequest:req
                                           queue:[NSOperationQueue mainQueue]
                               completionHandler:^(NSURLResponse *resp, NSData *data, NSError *err) {
            if (err) { callback(nil, err); return; }

            /* Limit response to 32KB to conserve memory */
            NSUInteger maxLen = 32768;
            NSData *truncated = [data length] > maxLen
                ? [data subdataWithRange:NSMakeRange(0, maxLen)]
                : data;
            NSString *text = [[NSString alloc] initWithData:truncated encoding:NSUTF8StringEncoding];
            callback(text ?: @"[Binary data]", nil);
            [text release];
        }];
    };
    return tool;
}

+ (OCToolDefinition *)fileReadTool {
    OCToolDefinition *tool = [[[OCToolDefinition alloc] init] autorelease];
    tool.name = @"read_file";
    tool.toolDescription = @"Read a text file from the device filesystem";
    tool.inputSchema = @{
        @"type": @"object",
        @"properties": @{
            @"path": @{@"type": @"string"}
        },
        @"required": @[@"path"]
    };
    tool.handler = ^(NSDictionary *params, OCToolResultBlock callback) {
        NSString *path = [params objectForKey:@"path"];
        NSError *error = nil;
        NSString *content = [NSString stringWithContentsOfFile:path
                                                      encoding:NSUTF8StringEncoding
                                                         error:&error];
        if (error) { callback(nil, error); return; }
        /* Truncate to 32KB */
        if ([content length] > 32768) {
            content = [content substringToIndex:32768];
        }
        callback(content, nil);
    };
    return tool;
}

+ (OCToolDefinition *)mathTool {
    OCToolDefinition *tool = [[[OCToolDefinition alloc] init] autorelease];
    tool.name = @"calculate";
    tool.toolDescription = @"Evaluate a mathematical expression";
    tool.inputSchema = @{
        @"type": @"object",
        @"properties": @{
            @"expression": @{@"type": @"string"}
        },
        @"required": @[@"expression"]
    };
    tool.handler = ^(NSDictionary *params, OCToolResultBlock callback) {
        NSString *expr = [params objectForKey:@"expression"];
        @try {
            NSExpression *mathExpr = [NSExpression expressionWithFormat:expr];
            id result = [mathExpr expressionValueWithObject:nil context:nil];
            callback([result description], nil);
        } @catch (NSException *e) {
            callback([NSString stringWithFormat:@"Error: %@", e.reason], nil);
        }
    };
    return tool;
}

+ (OCToolDefinition *)timerTool {
    OCToolDefinition *tool = [[[OCToolDefinition alloc] init] autorelease];
    tool.name = @"set_timer";
    tool.toolDescription = @"Set a timer that fires after N seconds";
    tool.inputSchema = @{
        @"type": @"object",
        @"properties": @{
            @"seconds": @{@"type": @"number"},
            @"label": @{@"type": @"string"}
        },
        @"required": @[@"seconds"]
    };
    tool.handler = ^(NSDictionary *params, OCToolResultBlock callback) {
        NSTimeInterval seconds = [[params objectForKey:@"seconds"] doubleValue];
        NSString *label = [params objectForKey:@"label"] ?: @"Timer";

        /* Schedule local notification via runtime for iOS 6 compat */
        Class notifClass = NSClassFromString(@"UILocalNotification");
        if (notifClass) {
            id notif = [[[notifClass alloc] init] autorelease];
            [notif setValue:[NSDate dateWithTimeIntervalSinceNow:seconds] forKey:@"fireDate"];
            [notif setValue:[NSString stringWithFormat:@"%@: Time's up!", label] forKey:@"alertBody"];
            [notif setValue:@"UILocalNotificationDefaultSoundName" forKey:@"soundName"];
            [[UIApplication sharedApplication] performSelector:@selector(scheduleLocalNotification:)
                                                    withObject:notif];
        }

        callback([NSString stringWithFormat:@"Timer set for %.0f seconds: %@", seconds, label], nil);
    };
    return tool;
}

@end
