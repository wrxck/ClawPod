/*
 * OCChatViewController.m
 * LegacyPodClaw - Chat View Controller
 *
 * iMessage-style chat with:
 * - Blue user bubbles (right), gray assistant bubbles (left)
 * - Immediate message display + auto-scroll
 * - Typing indicator while waiting for response
 * - Keyboard dismiss on tap outside
 * - Error popups when no connection/API key
 */

#import "ChatViewController.h"
#import "ChatCell.h"
#import "AppDelegate.h"
#import "TLSClient.h"

static const CGFloat kInputBarHeight = 44.0f;
static const CGFloat kMaxInputHeight = 100.0f;
static const CGFloat kTypingCellHeight = 40.0f;

@interface OCChatViewController () {
    UITableView *_tableView;
    UIView *_inputBar;
    UITextView *_inputTextView;
    UIButton *_sendButton;

    /* Keyboard tracking */
    CGFloat _keyboardHeight;

    /* State */
    BOOL _autoScrollEnabled;
    BOOL _isWaitingForResponse;
    NSTimer *_streamUpdateTimer;
    BOOL _needsStreamUpdate;

    /* Tap to dismiss keyboard */
    UITapGestureRecognizer *_tapDismiss;

    /* Status */
    UILabel *_statusLabel;

    /* Direct API mode */
    NSURLConnection *_directConn;
    NSMutableString *_directStreamBuf;
    NSMutableString *_directSSEBuf;
    NSMutableArray *_directHistory;   /* conversation history for API */
    NSMutableArray *_directMessages;  /* local message objects for display */

    /* Tool execution state */
    NSString *_pendingToolName;
    NSString *_pendingToolId;
    NSMutableString *_pendingToolInput;
    int _pendingStopReason;  /* 0 = none, 1 = tool_use */
    NSUInteger _toolStatusStart; /* position in _directStreamBuf where tool status starts */
}
@end

@implementation OCChatViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor whiteColor];
    _autoScrollEnabled = YES;
    _isWaitingForResponse = NO;

    [self _setupTableView];
    [self _setupInputBar];
    [self _registerKeyboardNotifications];

    /* Tap to dismiss keyboard */
    _tapDismiss = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_dismissKeyboard)];
    _tapDismiss.cancelsTouchesInView = NO;
    [_tableView addGestureRecognizer:_tapDismiss];

    /* Batch stream updates at 10fps */
    _streamUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                          target:self
                                                        selector:@selector(_flushStreamUpdates)
                                                        userInfo:nil
                                                         repeats:YES];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    OCSessionManager *mgr = [AppDelegate shared].sessionManager;

    /* Create a default session if none exist */
    if ([mgr.sessions count] == 0) {
        [mgr createSession:@"Untitled"];
    }

    /* Auto-select first session if none active */
    if (!mgr.activeSession && [mgr.sessions count] > 0) {
        OCChatSession *first = [mgr.sessions objectAtIndex:0];
        [mgr switchToSession:first.sessionKey];
    }

    /* Rebuild API conversation history from persisted messages (lazy, last 10) */
    if (mgr.activeSession && [mgr.activeSession.messages count] > 0 &&
        (!_directHistory || [_directHistory count] == 0)) {
        if (!_directHistory) _directHistory = [[NSMutableArray alloc] initWithCapacity:20];
        NSArray *msgs = mgr.activeSession.messages;
        NSUInteger start = [msgs count] > 10 ? [msgs count] - 10 : 0;
        for (NSUInteger i = start; i < [msgs count]; i++) {
            OCMessage *m = [msgs objectAtIndex:i];
            if (m.role == OCMessageRoleUser && m.content) {
                [_directHistory addObject:@{@"role": @"user", @"content": m.content}];
            } else if (m.role == OCMessageRoleAssistant && m.content) {
                [_directHistory addObject:@{@"role": @"assistant", @"content": m.content}];
            }
        }
    }

    [_tableView reloadData];
    [self _scrollToBottomAnimated:NO];
}

- (void)dealloc {
    [_streamUpdateTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_tableView release]; [_inputBar release]; [_inputTextView release];
    [_sendButton release]; [_tapDismiss release]; [_statusLabel release];
    [super dealloc];
}

#pragma mark - UI Setup

- (void)_setupTableView {
    CGRect bounds = self.view.bounds;
    CGRect tableFrame = CGRectMake(0, 0,
                                   bounds.size.width,
                                   bounds.size.height - kInputBarHeight);

    _tableView = [[UITableView alloc] initWithFrame:tableFrame style:UITableViewStylePlain];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.backgroundColor = [UIColor whiteColor];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.allowsSelection = NO;

    [self.view addSubview:_tableView];
}

- (void)_setupInputBar {
    CGRect bounds = self.view.bounds;
    CGFloat y = bounds.size.height - kInputBarHeight;

    _inputBar = [[UIView alloc] initWithFrame:CGRectMake(0, y, bounds.size.width, kInputBarHeight)];
    _inputBar.backgroundColor = [UIColor colorWithRed:0.97f green:0.97f blue:0.97f alpha:1.0f];
    _inputBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;

    /* Top border */
    UIView *border = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, bounds.size.width, 0.5f)] autorelease];
    border.backgroundColor = [UIColor colorWithWhite:0.75f alpha:1.0f];
    border.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_inputBar addSubview:border];

    /* Text input */
    CGFloat sendWidth = 56.0f;
    CGFloat textX = 8.0f;
    CGFloat textW = bounds.size.width - sendWidth - textX - 8.0f;

    _inputTextView = [[UITextView alloc] initWithFrame:
        CGRectMake(textX, 7, textW, kInputBarHeight - 14)];
    _inputTextView.delegate = self;
    _inputTextView.font = [UIFont systemFontOfSize:15.0f];
    _inputTextView.backgroundColor = [UIColor whiteColor];
    _inputTextView.layer.cornerRadius = 6.0f;
    _inputTextView.layer.borderColor = [[UIColor colorWithWhite:0.8f alpha:1.0f] CGColor];
    _inputTextView.layer.borderWidth = 0.5f;
    _inputTextView.layer.masksToBounds = YES;
    _inputTextView.returnKeyType = UIReturnKeySend;
    _inputTextView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_inputBar addSubview:_inputTextView];

    /* Send button */
    _sendButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _sendButton.frame = CGRectMake(bounds.size.width - sendWidth - 4, 7, sendWidth, kInputBarHeight - 14);
    [_sendButton setTitle:@"Send" forState:UIControlStateNormal];
    [_sendButton setTitleColor:[UIColor colorWithRed:0.0f green:0.478f blue:1.0f alpha:1.0f]
                      forState:UIControlStateNormal];
    [_sendButton setTitleColor:[UIColor lightGrayColor] forState:UIControlStateDisabled];
    _sendButton.titleLabel.font = [UIFont boldSystemFontOfSize:16.0f];
    _sendButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_sendButton addTarget:self action:@selector(_sendTapped) forControlEvents:UIControlEventTouchUpInside];
    _sendButton.enabled = NO;
    [_inputBar addSubview:_sendButton];

    [self.view addSubview:_inputBar];
}

#pragma mark - Keyboard Dismiss

- (void)_dismissKeyboard {
    [_inputTextView resignFirstResponder];
}

#pragma mark - Actions

- (void)_sendTapped {
    NSString *text = [_inputTextView.text stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([text length] == 0) return;

    /* Check connection / API key before sending */
    AppDelegate *app = [AppDelegate shared];
    OCGatewayConnectionState gwState = app.gateway.connectionState;

    if (gwState != OCGatewayStateConnected) {
        /* Check if local agent has API key */
        if (!app.localAgent.modelConfig.apiKey || [app.localAgent.modelConfig.apiKey length] == 0) {
            UIAlertView *alert = [[UIAlertView alloc]
                initWithTitle:@"Not Connected"
                      message:@"No gateway connection and no API key configured.\n\n"
                               "Go to Settings \u2192 LegacyPodClaw to set up a gateway or API key."
                     delegate:nil
            cancelButtonTitle:@"OK"
            otherButtonTitles:nil];
            [alert show];
            [alert release];
            return;
        }
    }

    _inputTextView.text = @"";
    _sendButton.enabled = NO;
    [self _updateInputBarHeight];

    _isWaitingForResponse = YES;
    _autoScrollEnabled = YES;

    if (gwState == OCGatewayStateConnected) {
        /* Gateway mode — use session manager */
        OCSessionManager *mgr = app.sessionManager;
        if (!mgr.activeSession) {
            [mgr createSession:@"New Chat"];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC),
                           dispatch_get_main_queue(), ^{
                [mgr sendMessage:text];
                [_tableView reloadData];
                [self _scrollToBottomAnimated:YES];
            });
        } else {
            [mgr sendMessage:text];
        }
    } else {
        /* Direct API mode — use local agent's HTTP client */
        [self _sendDirectAPI:text];
    }
}

#pragma mark - Direct API Mode

/* Update the streaming assistant bubble with the current buffer text */
- (void)_updateAssistantBubbleWithText:(NSString *)text {
    NSArray *msgs = [self _currentMessages];
    if ([msgs count] > 0) {
        OCMessage *last = [msgs lastObject];
        if (last.role == OCMessageRoleAssistant && last.state == OCMessageStateStreaming) {
            [last.streamBuffer setString:text ?: @""];
            _needsStreamUpdate = YES;
        }
    }
}

- (void)_sendDirectAPI:(NSString *)text {
    AppDelegate *app = [AppDelegate shared];

    if (!_directHistory) _directHistory = [[NSMutableArray alloc] initWithCapacity:20];
    if (!_directStreamBuf) _directStreamBuf = [[NSMutableString alloc] init];
    if (!_directSSEBuf) _directSSEBuf = [[NSMutableString alloc] init];

    /* Ensure we have an active session */
    OCSessionManager *mgr = app.sessionManager;
    if (!mgr.activeSession) {
        [mgr createSession:@"Untitled"];
        if (!mgr.activeSession) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
    }

    if (!_directMessages) _directMessages = [[NSMutableArray alloc] initWithCapacity:32];

    /* Show user message in UI immediately */
    OCMessage *userMsg = [OCMessage userMessage:text];
    if (mgr.activeSession) {
        [(NSMutableArray *)mgr.activeSession.messages addObject:userMsg];
        /* Persist user message to DB */
        [mgr persistMessage:userMsg sessionKey:mgr.activeSession.sessionKey];
    }
    [_directMessages addObject:userMsg];
    [_tableView reloadData];
    [self _scrollToBottomAnimated:YES];

    /* Create streaming placeholder */
    OCMessage *assistantMsg = [[[OCMessage alloc] init] autorelease];
    assistantMsg.role = OCMessageRoleAssistant;
    assistantMsg.state = OCMessageStateStreaming;
    if (mgr.activeSession) {
        [(NSMutableArray *)mgr.activeSession.messages addObject:assistantMsg];
    }
    [_directMessages addObject:assistantMsg];
    [_tableView reloadData];
    [self _scrollToBottomAnimated:YES];

    /* Build conversation history */
    [_directHistory addObject:@{@"role": @"user", @"content": text}];
    while ([_directHistory count] > 10) [_directHistory removeObjectAtIndex:0];

    /* API call via CPTLSClient (wolfSSL TLS 1.2) */
    NSString *apiKey = app.localAgent.modelConfig.apiKey;
    NSString *model = app.localAgent.modelConfig.modelId ?: @"claude-sonnet-4-20250514";

    NSDictionary *headers = @{
        @"Content-Type": @"application/json",
        @"anthropic-version": @"2023-06-01",
        @"x-api-key": apiKey,
        @"Accept": @"text/event-stream"
    };

    /* Build tool definitions from registered tools (ensure unique names) */
    NSMutableArray *toolDefs = [NSMutableArray array];
    NSMutableSet *seenNames = [NSMutableSet set];
    for (OCToolDefinition *tool in [app.localAgent registeredTools]) {
        if (!tool.name || [seenNames containsObject:tool.name]) continue;
        [seenNames addObject:tool.name];
        [toolDefs addObject:@{
            @"name": tool.name,
            @"description": tool.toolDescription ?: @"",
            @"input_schema": tool.inputSchema ?: @{@"type": @"object", @"properties": @{}}
        }];
    }

    NSMutableDictionary *body = [NSMutableDictionary dictionaryWithCapacity:8];
    [body setObject:model forKey:@"model"];
    [body setObject:@(4096) forKey:@"max_tokens"];
    [body setObject:@YES forKey:@"stream"];
    [body setObject:app.localAgent.systemPrompt ?: @"You are a helpful AI assistant." forKey:@"system"];
    [body setObject:_directHistory forKey:@"messages"];
    if ([toolDefs count] > 0) {
        [body setObject:toolDefs forKey:@"tools"];
    }
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    [_directStreamBuf setString:@""];
    [_directSSEBuf setString:@""];
    _toolStatusStart = 0;
    _pendingStopReason = 0;

    [self _executeAPIRequest:bodyData headers:headers];
}

/* Execute an API request and handle the full agent loop (text + tool calls) */
- (void)_executeAPIRequest:(NSData *)bodyData headers:(NSDictionary *)headers {
    AppDelegate *app = [AppDelegate shared];

    [CPTLSClient streamRequest:@"https://api.anthropic.com/v1/messages"
                        method:@"POST"
                       headers:headers
                          body:bodyData
                       onChunk:^(NSData *chunk) {
        NSString *chunkStr = [[NSString alloc] initWithData:chunk encoding:NSUTF8StringEncoding];
        if (!chunkStr) { [chunkStr release]; return; }
        [_directSSEBuf appendString:chunkStr];
        [chunkStr release];

        NSArray *lines = [_directSSEBuf componentsSeparatedByString:@"\n"];
        [_directSSEBuf setString:[lines lastObject] ?: @""];

        for (NSUInteger i = 0; i < [lines count] - 1; i++) {
            NSString *line = [lines objectAtIndex:i];
            NSString *trimmed = [line stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            /* Skip chunked encoding hex lines */
            if ([trimmed length] > 0 && [trimmed length] <= 8) {
                BOOL isHex = YES;
                for (NSUInteger ci = 0; ci < [trimmed length]; ci++) {
                    unichar ch = [trimmed characterAtIndex:ci];
                    if (!((ch>='0'&&ch<='9')||(ch>='a'&&ch<='f')||(ch>='A'&&ch<='F')))
                        { isHex = NO; break; }
                }
                if (isHex) continue;
            }
            if (![line hasPrefix:@"data: "]) continue;
            NSString *json = [line substringFromIndex:6];
            if ([json isEqualToString:@"[DONE]"]) continue;

            NSDictionary *evt = [NSJSONSerialization JSONObjectWithData:
                [json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
            if (!evt) continue;

            NSString *evtType = [evt objectForKey:@"type"];

            /* Text streaming */
            if ([evtType isEqualToString:@"content_block_delta"]) {
                NSDictionary *delta = [evt objectForKey:@"delta"];
                NSString *deltaType = [delta objectForKey:@"type"];

                if ([deltaType isEqualToString:@"text_delta"]) {
                    NSString *text = [delta objectForKey:@"text"];
                    if (text) {
                        [_directStreamBuf appendString:text];
                        NSArray *msgs = [self _currentMessages];
                        if ([msgs count] > 0) {
                            OCMessage *last = [msgs lastObject];
                            if (last.role == OCMessageRoleAssistant && last.state == OCMessageStateStreaming) {
                                [last appendDelta:text];
                                _needsStreamUpdate = YES;
                            }
                        }
                    }
                }
                /* Tool input JSON delta — accumulate for tool execution */
                else if ([deltaType isEqualToString:@"input_json_delta"]) {
                    NSString *partial = [delta objectForKey:@"partial_json"];
                    if (partial) {
                        if (!_pendingToolInput) _pendingToolInput = [[NSMutableString alloc] init];
                        [_pendingToolInput appendString:partial];
                    }
                }
            }
            /* Tool use started */
            else if ([evtType isEqualToString:@"content_block_start"]) {
                NSDictionary *block = [evt objectForKey:@"content_block"];
                if ([[block objectForKey:@"type"] isEqualToString:@"tool_use"]) {
                    [_pendingToolName release];
                    _pendingToolName = [[block objectForKey:@"name"] copy];
                    [_pendingToolId release];
                    _pendingToolId = [[block objectForKey:@"id"] copy];
                    [_pendingToolInput release];
                    _pendingToolInput = [[NSMutableString alloc] init];

                    /* Show tool status — always replace from the same position */
                    if (_toolStatusStart == 0) _toolStatusStart = [_directStreamBuf length];
                    /* Replace everything from tool status start onwards */
                    if (_toolStatusStart <= [_directStreamBuf length]) {
                        [_directStreamBuf replaceCharactersInRange:
                            NSMakeRange(_toolStatusStart, [_directStreamBuf length] - _toolStatusStart)
                            withString:[NSString stringWithFormat:@"\n> %@...", _pendingToolName]];
                    }
                    [self _updateAssistantBubbleWithText:_directStreamBuf];
                }
            }
            /* Message complete — check if we need to execute tools */
            else if ([evtType isEqualToString:@"message_delta"]) {
                NSDictionary *msgDelta = [evt objectForKey:@"delta"];
                NSString *stopReason = [msgDelta objectForKey:@"stop_reason"];
                if ([stopReason isEqualToString:@"tool_use"]) {
                    _pendingStopReason = 1; /* Flag for tool execution */
                }
            }
        }
    }
                    completion:^(NSData *data, NSInteger statusCode, NSError *error) {
        if (error) {
            _isWaitingForResponse = NO;
            NSArray *msgs = [self _currentMessages];
            if ([msgs count] > 0) {
                OCMessage *last = [msgs lastObject];
                if (last.role == OCMessageRoleAssistant) {
                    [last.streamBuffer setString:[NSString stringWithFormat:@"Error: %@",
                        [error localizedDescription]]];
                    [last finalizeStream];
                    last.state = OCMessageStateError;
                }
            }
            [_tableView reloadData];
            return;
        }

        /* If model stopped for tool_use, execute the tool and continue */
        if (_pendingStopReason == 1 && _pendingToolName) {
            [self _executeToolAndContinue:headers];
            return;
        }

        /* Normal completion — finalize */
        _isWaitingForResponse = NO;
        NSArray *msgs = [self _currentMessages];
        if ([msgs count] > 0) {
            OCMessage *last = [msgs lastObject];
            if (last.role == OCMessageRoleAssistant) {
                [last finalizeStream];
            }
        }

        if ([_directStreamBuf length] > 0) {
            [_directHistory addObject:@{@"role": @"assistant",
                @"content": [[_directStreamBuf copy] autorelease]}];
        }

        /* Persist completed assistant message to DB */
        OCSessionManager *mgr = [AppDelegate shared].sessionManager;
        if (mgr.activeSession) {
            NSArray *msgs = [self _currentMessages];
            if ([msgs count] > 0) {
                OCMessage *last = [msgs lastObject];
                if (last.role == OCMessageRoleAssistant && last.content) {
                    [mgr persistMessage:last sessionKey:mgr.activeSession.sessionKey];
                }
            }
        }

        [_tableView reloadData];
        [self _scrollToBottomAnimated:YES];
    }];
}

/* Execute a pending tool call and send the result back to continue the conversation */
- (void)_executeToolAndContinue:(NSDictionary *)headers {
    AppDelegate *app = [AppDelegate shared];

    /* Parse tool input */
    NSDictionary *toolInput = nil;
    if (_pendingToolInput && [_pendingToolInput length] > 0) {
        toolInput = [NSJSONSerialization JSONObjectWithData:
            [_pendingToolInput dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    }

    /* Find and execute the tool */
    NSString *toolName = [[_pendingToolName copy] autorelease];
    NSString *toolId = [[_pendingToolId copy] autorelease];

    OCToolDefinition *tool = nil;
    for (OCToolDefinition *t in [app.localAgent registeredTools]) {
        if ([t.name isEqualToString:toolName]) { tool = t; break; }
    }

    if (!tool || !tool.handler) {
        /* Tool not found — send error back */
        [self _sendToolResult:toolId result:@"Tool not found" headers:headers];
        return;
    }

    /* Update status to "Running..." — replace from tool status start */
    if (_toolStatusStart <= [_directStreamBuf length]) {
        [_directStreamBuf replaceCharactersInRange:
            NSMakeRange(_toolStatusStart, [_directStreamBuf length] - _toolStatusStart)
            withString:[NSString stringWithFormat:@"\n> Running %@...", toolName]];
        [self _updateAssistantBubbleWithText:_directStreamBuf];
    }

    /* Execute tool */
    tool.handler(toolInput ?: @{}, ^(id result, NSError *err) {
        NSString *resultStr;
        if (err) {
            resultStr = [NSString stringWithFormat:@"Error: %@", [err localizedDescription]];
        } else if ([result isKindOfClass:[NSString class]]) {
            resultStr = result;
        } else {
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:result ?: @{} options:0 error:nil];
            resultStr = [[[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] autorelease];
        }

        /* Clear tool status — the model's next response will replace it */
        if (_toolStatusStart <= [_directStreamBuf length]) {
            [_directStreamBuf replaceCharactersInRange:
                NSMakeRange(_toolStatusStart, [_directStreamBuf length] - _toolStatusStart)
                withString:@""];
        }
        /* Reset tool status position so next tool or text starts fresh */
        _toolStatusStart = 0;

        [self _sendToolResult:toolId result:resultStr headers:headers];
    });
}

/* Send tool result back to API and continue the conversation */
- (void)_sendToolResult:(NSString *)toolId result:(NSString *)result headers:(NSDictionary *)headers {
    AppDelegate *app = [AppDelegate shared];

    /* Add assistant tool_use + user tool_result to history */
    [_directHistory addObject:@{@"role": @"assistant", @"content": @[
        @{@"type": @"tool_use", @"id": toolId ?: @"", @"name": _pendingToolName ?: @"",
          @"input": [NSJSONSerialization JSONObjectWithData:
              [_pendingToolInput ?: @"{}" dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] ?: @{}}
    ]}];
    [_directHistory addObject:@{@"role": @"user", @"content": @[
        @{@"type": @"tool_result", @"tool_use_id": toolId ?: @"", @"content": result ?: @""}
    ]}];

    /* Reset tool state */
    _pendingStopReason = 0;
    [_pendingToolName release]; _pendingToolName = nil;
    [_pendingToolId release]; _pendingToolId = nil;
    [_pendingToolInput release]; _pendingToolInput = nil;
    [_directSSEBuf setString:@""];

    /* Build next request body */
    NSString *model = app.localAgent.modelConfig.modelId ?: @"claude-sonnet-4-20250514";
    NSMutableArray *toolDefs = [NSMutableArray array];
    NSMutableSet *seenNames = [NSMutableSet set];
    for (OCToolDefinition *t in [app.localAgent registeredTools]) {
        if (!t.name || [seenNames containsObject:t.name]) continue;
        [seenNames addObject:t.name];
        [toolDefs addObject:@{
            @"name": t.name,
            @"description": t.toolDescription ?: @"",
            @"input_schema": t.inputSchema ?: @{@"type": @"object", @"properties": @{}}
        }];
    }

    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    [body setObject:model forKey:@"model"];
    [body setObject:@(4096) forKey:@"max_tokens"];
    [body setObject:@YES forKey:@"stream"];
    [body setObject:app.localAgent.systemPrompt ?: @"" forKey:@"system"];
    [body setObject:_directHistory forKey:@"messages"];
    if ([toolDefs count] > 0) [body setObject:toolDefs forKey:@"tools"];

    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    /* Continue the agent loop */
    [self _executeAPIRequest:bodyData headers:headers];
}

/* NSURLConnection delegates removed — using CPTLSClient for direct API */

#pragma mark - Public Updates

- (void)updateStatusText:(NSString *)text color:(UIColor *)color {
    /* Status shown in nav title by RootViewController */
}

- (void)didReceiveMessage:(OCMessage *)message {
    _isWaitingForResponse = NO;
    [_tableView reloadData];
    if (_autoScrollEnabled) {
        [self _scrollToBottomAnimated:YES];
    }
}

- (void)didUpdateStreamingMessage:(OCMessage *)message {
    _needsStreamUpdate = YES;
}

- (void)_flushStreamUpdates {
    if (!_needsStreamUpdate) return;
    _needsStreamUpdate = NO;

    NSArray *messages = [self _currentMessages];
    if ([messages count] == 0) return;

    /* Reload last row for streaming content */
    NSUInteger lastIdx = [messages count] - 1;
    /* Add 1 if typing indicator is showing */
    if (_isWaitingForResponse) lastIdx = [messages count] - 1;

    NSIndexPath *ip = [NSIndexPath indexPathForRow:lastIdx inSection:0];
    OCChatCell *cell = (OCChatCell *)[_tableView cellForRowAtIndexPath:ip];
    if (cell) {
        OCMessage *msg = [messages objectAtIndex:lastIdx];
        [cell configureWithMessage:msg];
        /* Recalculate height */
        [_tableView beginUpdates];
        [_tableView endUpdates];
    } else {
        [_tableView reloadData];
    }

    if (_autoScrollEnabled) {
        [self _scrollToBottomAnimated:NO];
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger count = [[self _currentMessages] count];
    /* Only add separate typing row if no messages exist yet
       (in direct API mode the streaming message is already in the array) */
    if (_isWaitingForResponse && count == 0) count = 1;
    return count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {

    NSArray *messages = [self _currentMessages];

    /* Typing indicator cell */
    if (_isWaitingForResponse && indexPath.row == (NSInteger)[messages count]) {
        static NSString *typingId = @"TypingCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:typingId];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                          reuseIdentifier:typingId] autorelease];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.backgroundColor = [UIColor whiteColor];

            /* Typing bubble */
            UIView *bubble = [[[UIView alloc] initWithFrame:CGRectMake(10, 4, 60, 32)] autorelease];
            bubble.backgroundColor = [UIColor colorWithRed:0.89f green:0.90f blue:0.91f alpha:1.0f];
            bubble.layer.cornerRadius = 16.0f;
            bubble.tag = 100;
            [cell.contentView addSubview:bubble];

            /* Three dots */
            for (int i = 0; i < 3; i++) {
                UIView *dot = [[[UIView alloc] initWithFrame:
                    CGRectMake(14 + i * 14, 12, 8, 8)] autorelease];
                dot.backgroundColor = [UIColor colorWithWhite:0.55f alpha:1.0f];
                dot.layer.cornerRadius = 4.0f;
                dot.tag = 200 + i;
                [bubble addSubview:dot];
            }
        }

        /* Animate dots */
        UIView *bubble = [cell.contentView viewWithTag:100];
        for (int i = 0; i < 3; i++) {
            UIView *dot = [bubble viewWithTag:200 + i];
            [UIView animateWithDuration:0.4
                                  delay:i * 0.15
                                options:UIViewAnimationOptionRepeat | UIViewAnimationOptionAutoreverse
                             animations:^{
                dot.alpha = 0.3f;
            } completion:nil];
        }

        return cell;
    }

    /* Message cell */
    static NSString *cellId = @"ChatCell";
    OCChatCell *cell = (OCChatCell *)[tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[[OCChatCell alloc] initWithStyle:UITableViewCellStyleDefault
                                  reuseIdentifier:cellId] autorelease];
    }

    if (indexPath.row < (NSInteger)[messages count]) {
        OCMessage *msg = [messages objectAtIndex:indexPath.row];
        [cell configureWithMessage:msg];
    }

    return cell;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *messages = [self _currentMessages];

    /* Typing indicator row */
    if (_isWaitingForResponse && indexPath.row == (NSInteger)[messages count]) {
        return kTypingCellHeight;
    }

    if (indexPath.row >= (NSInteger)[messages count]) return 44.0f;

    OCMessage *msg = [messages objectAtIndex:indexPath.row];
    return [OCChatCell heightForMessage:msg width:tableView.bounds.size.width];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    _autoScrollEnabled = NO;
    [self _dismissKeyboard];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    CGFloat offset = scrollView.contentOffset.y;
    CGFloat maxOffset = scrollView.contentSize.height - scrollView.bounds.size.height;
    if (maxOffset - offset < 50) {
        _autoScrollEnabled = YES;
    }
}

#pragma mark - UITextViewDelegate

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range
 replacementText:(NSString *)text {
    if ([text isEqualToString:@"\n"]) {
        [self _sendTapped];
        return NO;
    }
    return YES;
}

- (void)textViewDidChange:(UITextView *)textView {
    _sendButton.enabled = [[textView.text stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]] length] > 0;
    [self _updateInputBarHeight];
}

#pragma mark - Keyboard

- (void)_registerKeyboardNotifications {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(_keyboardWillShow:)
               name:UIKeyboardWillShowNotification object:nil];
    [nc addObserver:self selector:@selector(_keyboardWillHide:)
               name:UIKeyboardWillHideNotification object:nil];
}

- (void)_keyboardWillShow:(NSNotification *)notif {
    NSDictionary *info = [notif userInfo];
    CGRect keyboardFrame = [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    NSTimeInterval duration = [[info objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve = [[info objectForKey:UIKeyboardAnimationCurveUserInfoKey] intValue];

    _keyboardHeight = keyboardFrame.size.height;

    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:duration];
    [UIView setAnimationCurve:curve];

    CGRect bounds = self.view.bounds;
    CGFloat inputH = _inputBar.frame.size.height;
    CGFloat inputY = bounds.size.height - _keyboardHeight - inputH;
    _inputBar.frame = CGRectMake(0, inputY, bounds.size.width, inputH);
    _tableView.frame = CGRectMake(0, 0, bounds.size.width, inputY);

    [UIView commitAnimations];

    if (_autoScrollEnabled) {
        [self _scrollToBottomAnimated:YES];
    }
}

- (void)_keyboardWillHide:(NSNotification *)notif {
    NSDictionary *info = [notif userInfo];
    NSTimeInterval duration = [[info objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve = [[info objectForKey:UIKeyboardAnimationCurveUserInfoKey] intValue];

    _keyboardHeight = 0;

    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:duration];
    [UIView setAnimationCurve:curve];

    CGRect bounds = self.view.bounds;
    CGFloat inputH = _inputBar.frame.size.height;
    CGFloat inputY = bounds.size.height - inputH;
    _inputBar.frame = CGRectMake(0, inputY, bounds.size.width, inputH);
    _tableView.frame = CGRectMake(0, 0, bounds.size.width, inputY);

    [UIView commitAnimations];
}

#pragma mark - Helpers

- (NSArray *)_currentMessages {
    OCChatSession *session = [AppDelegate shared].sessionManager.activeSession;
    if (session && [session.messages count] > 0) return session.messages;
    /* Fall back to direct mode messages */
    if (_directMessages && [_directMessages count] > 0) return _directMessages;
    return @[];
}

- (void)_scrollToBottomAnimated:(BOOL)animated {
    NSInteger count = [_tableView numberOfRowsInSection:0];
    if (count == 0) return;

    NSIndexPath *lastIP = [NSIndexPath indexPathForRow:count - 1 inSection:0];
    [_tableView scrollToRowAtIndexPath:lastIP
                      atScrollPosition:UITableViewScrollPositionBottom
                              animated:animated];
}

- (void)_updateInputBarHeight {
    CGSize textSize = [_inputTextView.text sizeWithFont:_inputTextView.font
                                      constrainedToSize:CGSizeMake(_inputTextView.frame.size.width - 16,
                                                                   kMaxInputHeight)
                                          lineBreakMode:NSLineBreakByWordWrapping];

    CGFloat newHeight = MAX(kInputBarHeight, textSize.height + 20);
    newHeight = MIN(newHeight, kMaxInputHeight);

    if (fabs(newHeight - _inputBar.frame.size.height) < 1.0f) return;

    CGRect bounds = self.view.bounds;
    CGFloat inputY = bounds.size.height - _keyboardHeight - newHeight;

    [UIView animateWithDuration:0.15 animations:^{
        _inputBar.frame = CGRectMake(0, inputY, bounds.size.width, newHeight);
        _inputTextView.frame = CGRectMake(8, 7, _inputTextView.frame.size.width, newHeight - 14);
        _tableView.frame = CGRectMake(0, 0, bounds.size.width, inputY);
    }];
}

@end
