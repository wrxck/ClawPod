/*
 * OCChatSession.m
 * LegacyPodClaw - Chat Session & Message Implementation
 *
 * Memory-efficient message windowing: only keeps last N messages
 * in RAM, rest persisted to SQLite. Streaming delta assembly
 * with minimal allocations.
 */

#import "ChatSession.h"

#pragma mark - OCMessage

@implementation OCMessage

@synthesize streamBuffer = _streamBuffer;

- (instancetype)init {
    if ((self = [super init])) {
        _messageId = [[self _generateId] retain];
        _timestamp = [[NSDate date] retain];
        _state = OCMessageStateComplete;
    }
    return self;
}

- (void)dealloc {
    [_messageId release]; [_content release]; [_thinking release];
    [_timestamp release]; [_stopReason release]; [_runId release];
    [_streamBuffer release];
    [super dealloc];
}

- (NSMutableString *)streamBuffer {
    if (!_streamBuffer) {
        _streamBuffer = [[NSMutableString alloc] initWithCapacity:256];
    }
    return _streamBuffer;
}

- (void)appendDelta:(NSString *)delta {
    if (!delta) return;
    _state = OCMessageStateStreaming;
    [self.streamBuffer appendString:delta];
}

- (void)finalizeStream {
    if (_streamBuffer) {
        [_content release];
        _content = [_streamBuffer copy];
        [_streamBuffer release];
        _streamBuffer = nil;
    }
    _state = OCMessageStateComplete;
}

- (NSUInteger)estimatedMemoryCost {
    NSUInteger cost = 64; /* Base object overhead */
    cost += [_content length] * 2;   /* UTF-16 characters */
    cost += [_thinking length] * 2;
    cost += [_streamBuffer length] * 2;
    cost += [_messageId length] * 2;
    return cost;
}

+ (OCMessage *)userMessage:(NSString *)content {
    OCMessage *msg = [[[OCMessage alloc] init] autorelease];
    msg.role = OCMessageRoleUser;
    msg.content = content;
    return msg;
}

+ (OCMessage *)systemMessage:(NSString *)content {
    OCMessage *msg = [[[OCMessage alloc] init] autorelease];
    msg.role = OCMessageRoleSystem;
    msg.content = content;
    return msg;
}

- (NSString *)_generateId {
    CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
    NSString *str = (NSString *)CFUUIDCreateString(kCFAllocatorDefault, uuid);
    CFRelease(uuid);
    return [str autorelease];
}

#pragma mark - NSCoding

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:_messageId forKey:@"id"];
    [coder encodeInteger:_role forKey:@"role"];
    [coder encodeInteger:_state forKey:@"state"];
    [coder encodeObject:_content forKey:@"content"];
    [coder encodeObject:_thinking forKey:@"thinking"];
    [coder encodeObject:_timestamp forKey:@"ts"];
    [coder encodeInteger:_inputTokens forKey:@"itok"];
    [coder encodeInteger:_outputTokens forKey:@"otok"];
    [coder encodeObject:_stopReason forKey:@"stop"];
    [coder encodeObject:_runId forKey:@"rid"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super init])) {
        _messageId = [[coder decodeObjectForKey:@"id"] retain];
        _role = [coder decodeIntegerForKey:@"role"];
        _state = [coder decodeIntegerForKey:@"state"];
        _content = [[coder decodeObjectForKey:@"content"] retain];
        _thinking = [[coder decodeObjectForKey:@"thinking"] retain];
        _timestamp = [[coder decodeObjectForKey:@"ts"] retain];
        _inputTokens = [coder decodeIntegerForKey:@"itok"];
        _outputTokens = [coder decodeIntegerForKey:@"otok"];
        _stopReason = [[coder decodeObjectForKey:@"stop"] retain];
        _runId = [[coder decodeObjectForKey:@"rid"] retain];
    }
    return self;
}

@end

#pragma mark - OCAttachment

@implementation OCAttachment

- (void)dealloc {
    [_type release]; [_mimeType release]; [_fileName release];
    [_data release]; [_url release];
    [super dealloc];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:_type forKey:@"type"];
    [coder encodeObject:_mimeType forKey:@"mime"];
    [coder encodeObject:_fileName forKey:@"name"];
    [coder encodeObject:_url forKey:@"url"];
    [coder encodeInteger:_sizeBytes forKey:@"size"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super init])) {
        _type = [[coder decodeObjectForKey:@"type"] retain];
        _mimeType = [[coder decodeObjectForKey:@"mime"] retain];
        _fileName = [[coder decodeObjectForKey:@"name"] retain];
        _url = [[coder decodeObjectForKey:@"url"] retain];
        _sizeBytes = [coder decodeIntegerForKey:@"size"];
    }
    return self;
}

@end

#pragma mark - OCChatSession

@interface OCChatSession () {
    @public
    NSMutableArray *_messages;
}
@end

@implementation OCChatSession

@synthesize messages = _messages;

- (instancetype)init {
    if ((self = [super init])) {
        _messages = [[NSMutableArray alloc] initWithCapacity:50];
        _messageWindowSize = 50;
        _createdAt = [[NSDate date] retain];
        _lastActiveAt = [[NSDate date] retain];
    }
    return self;
}

- (void)dealloc {
    [_sessionKey release]; [_displayName release];
    [_createdAt release]; [_lastActiveAt release];
    [_messages release];
    [super dealloc];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:_sessionKey forKey:@"key"];
    [coder encodeObject:_displayName forKey:@"name"];
    [coder encodeObject:_createdAt forKey:@"created"];
    [coder encodeObject:_lastActiveAt forKey:@"active"];
    [coder encodeInteger:_totalMessages forKey:@"total"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super init])) {
        _sessionKey = [[coder decodeObjectForKey:@"key"] retain];
        _displayName = [[coder decodeObjectForKey:@"name"] retain];
        _createdAt = [[coder decodeObjectForKey:@"created"] retain];
        _lastActiveAt = [[coder decodeObjectForKey:@"active"] retain];
        _totalMessages = [coder decodeIntegerForKey:@"total"];
        _messages = [[NSMutableArray alloc] initWithCapacity:50];
        _messageWindowSize = 50;
    }
    return self;
}

@end

#pragma mark - OCSessionManager

@interface OCSessionManager () {
    OCStore *_store;
    OCGatewayClient *_gateway;
    NSMutableArray *_sessions;
    NSMutableDictionary *_activeStreams;  /* runId -> OCMessage (streaming) */
    OCChatSession *_activeSession;
}
@end

@implementation OCSessionManager

@synthesize sessions = _sessions;
@synthesize activeSession = _activeSession;

- (instancetype)initWithStore:(OCStore *)store
                gatewayClient:(OCGatewayClient *)gateway {
    if ((self = [super init])) {
        _store = [store retain];
        _gateway = [gateway retain];
        _sessions = [[NSMutableArray alloc] initWithCapacity:8];
        _activeStreams = [[NSMutableDictionary alloc] initWithCapacity:2];
    }
    return self;
}

- (void)dealloc {
    [_store release]; [_gateway release];
    [_sessions release]; [_activeStreams release];
    [_activeSession release];
    [super dealloc];
}

#pragma mark - Schema

- (BOOL)setupSchema:(NSError **)error {
    NSString *sessionsSQL =
        @"CREATE TABLE IF NOT EXISTS sessions ("
        @"  key TEXT PRIMARY KEY,"
        @"  display_name TEXT,"
        @"  created_at REAL,"
        @"  last_active_at REAL,"
        @"  total_messages INTEGER DEFAULT 0"
        @")";

    NSString *messagesSQL =
        @"CREATE TABLE IF NOT EXISTS messages ("
        @"  id TEXT PRIMARY KEY,"
        @"  session_key TEXT NOT NULL,"
        @"  role INTEGER NOT NULL,"
        @"  content TEXT,"
        @"  thinking TEXT,"
        @"  timestamp REAL,"
        @"  input_tokens INTEGER DEFAULT 0,"
        @"  output_tokens INTEGER DEFAULT 0,"
        @"  stop_reason TEXT,"
        @"  run_id TEXT,"
        @"  FOREIGN KEY (session_key) REFERENCES sessions(key)"
        @")";

    NSString *indexSQL =
        @"CREATE INDEX IF NOT EXISTS idx_messages_session "
        @"ON messages(session_key, timestamp DESC)";

    if (![_store execute:sessionsSQL error:error]) return NO;
    if (![_store execute:messagesSQL error:error]) return NO;
    if (![_store execute:indexSQL error:error]) return NO;
    return YES;
}

#pragma mark - Session Operations

- (void)loadSessions {
    /* First load from local DB */
    [_sessions removeAllObjects];
    [_store query:@"SELECT * FROM sessions ORDER BY last_active_at DESC"
           params:nil
        enumerate:^(OCStoreRow *row, BOOL *stop) {
            OCChatSession *session = [[OCChatSession alloc] init];
            session.sessionKey = [row stringForColumn:@"key"];
            session.displayName = [row stringForColumn:@"display_name"];
            session.totalMessages = [row integerForColumn:@"total_messages"];
            session.createdAt = [NSDate dateWithTimeIntervalSince1970:
                                 [row doubleForColumn:@"created_at"]];
            session.lastActiveAt = [NSDate dateWithTimeIntervalSince1970:
                                    [row doubleForColumn:@"last_active_at"]];
            [_sessions addObject:session];
            [session release];
        } error:nil];

    /* Notify UI of local sessions immediately */
    dispatch_async(dispatch_get_main_queue(), ^{
        [_delegate sessionManager:self didUpdateSession:nil];
    });

    /* Also sync from gateway */
    [_gateway listSessions:^(NSArray *remoteSessions, NSError *error) {
        if (error || !remoteSessions) return;

        for (OCGatewaySession *remote in remoteSessions) {
            BOOL found = NO;
            for (OCChatSession *local in _sessions) {
                if ([local.sessionKey isEqualToString:remote.key]) {
                    found = YES;
                    break;
                }
            }
            if (!found) {
                OCChatSession *session = [[OCChatSession alloc] init];
                session.sessionKey = remote.key;
                session.displayName = remote.displayName;
                session.createdAt = remote.createdAt ?: [NSDate date];
                session.lastActiveAt = remote.lastActiveAt ?: [NSDate date];
                [_sessions addObject:session];
                [self _persistSession:session];
                [session release];
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [_delegate sessionManager:self didUpdateSession:nil];
        });
    }];
}

- (void)createSession:(NSString *)displayName {
    /* Try gateway first, fall back to local-only session */
    if (_gateway && _gateway.connectionState == OCGatewayStateConnected) {
        [_gateway createSession:displayName callback:^(NSDictionary *result, NSError *error) {
            if (error) {
                [self _createLocalSession:displayName];
                return;
            }
            NSString *key = [result objectForKey:@"key"] ?: [result objectForKey:@"sessionKey"];
            if (!key) { [self _createLocalSession:displayName]; return; }

            OCChatSession *session = [[OCChatSession alloc] init];
            session.sessionKey = key;
            session.displayName = displayName;
            [_sessions insertObject:session atIndex:0];
            [self _persistSession:session];
            dispatch_async(dispatch_get_main_queue(), ^{
                [_delegate sessionManager:self didUpdateSession:session];
            });
            [self switchToSession:key];
            [session release];
        }];
    } else {
        [self _createLocalSession:displayName];
    }
}

- (void)_createLocalSession:(NSString *)displayName {
    /* Create a local-only session (no gateway needed) */
    CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
    NSString *key = [(NSString *)CFUUIDCreateString(kCFAllocatorDefault, uuid) autorelease];
    CFRelease(uuid);

    OCChatSession *session = [[OCChatSession alloc] init];
    session.sessionKey = key;
    session.displayName = displayName ?: @"New Chat";
    [_sessions insertObject:session atIndex:0];
    [self _persistSession:session];

    dispatch_async(dispatch_get_main_queue(), ^{
        [_delegate sessionManager:self didUpdateSession:session];
    });

    [self switchToSession:key];
    [session release];
}

- (void)switchToSession:(NSString *)sessionKey {
    /* Unsubscribe from old session */
    if (_activeSession) {
        [_gateway unsubscribeSession:_activeSession.sessionKey];
    }

    /* Find session */
    for (OCChatSession *session in _sessions) {
        if ([session.sessionKey isEqualToString:sessionKey]) {
            [_activeSession release];
            _activeSession = [session retain];
            _activeSession.isActive = YES;

            /* Load messages from local DB */
            NSArray *messages = [self loadMessages:sessionKey
                                            limit:session.messageWindowSize
                                           offset:0];
            [session->_messages removeAllObjects];
            [session->_messages addObjectsFromArray:messages];

            /* Subscribe to events */
            [_gateway subscribeSession:sessionKey];

            dispatch_async(dispatch_get_main_queue(), ^{
                [_delegate sessionManager:self didUpdateSession:session];
            });
            return;
        }
    }
}

- (void)deleteSession:(NSString *)sessionKey {
    [_gateway deleteSession:sessionKey callback:^(NSDictionary *result, NSError *error) {
        [_store execute:@"DELETE FROM messages WHERE session_key = ?"
                 params:@[sessionKey] error:nil];
        [_store execute:@"DELETE FROM sessions WHERE key = ?"
                 params:@[sessionKey] error:nil];

        for (NSUInteger i = 0; i < [_sessions count]; i++) {
            OCChatSession *s = [_sessions objectAtIndex:i];
            if ([s.sessionKey isEqualToString:sessionKey]) {
                [_sessions removeObjectAtIndex:i];
                break;
            }
        }

        if ([_activeSession.sessionKey isEqualToString:sessionKey]) {
            [_activeSession release];
            _activeSession = nil;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [_delegate sessionManager:self didUpdateSession:nil];
        });
    }];
}

- (void)resetSession:(NSString *)sessionKey {
    [_gateway resetSession:sessionKey callback:^(NSDictionary *result, NSError *error) {
        [_store execute:@"DELETE FROM messages WHERE session_key = ?"
                 params:@[sessionKey] error:nil];
        [_store execute:@"UPDATE sessions SET total_messages = 0 WHERE key = ?"
                 params:@[sessionKey] error:nil];

        for (OCChatSession *s in _sessions) {
            if ([s.sessionKey isEqualToString:sessionKey]) {
                [s->_messages removeAllObjects];
                s.totalMessages = 0;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [_delegate sessionManager:self didUpdateSession:s];
                });
                break;
            }
        }
    }];
}

#pragma mark - Messaging

- (void)sendMessage:(NSString *)text {
    [self sendMessage:text withAttachments:nil];
}

- (void)sendMessage:(NSString *)text withAttachments:(NSArray *)attachments {
    if (!_activeSession || !text) return;

    /* Create and display user message immediately */
    OCMessage *userMsg = [OCMessage userMessage:text];
    [_activeSession->_messages addObject:userMsg];
    [self persistMessage:userMsg sessionKey:_activeSession.sessionKey];

    dispatch_async(dispatch_get_main_queue(), ^{
        [_delegate sessionManager:self didReceiveMessage:userMsg
                        inSession:_activeSession];
    });

    /* Create placeholder for assistant response */
    OCMessage *assistantMsg = [[[OCMessage alloc] init] autorelease];
    assistantMsg.role = OCMessageRoleAssistant;
    assistantMsg.state = OCMessageStateStreaming;
    [_activeSession->_messages addObject:assistantMsg];

    NSString *sessionKey = _activeSession.sessionKey;
    NSString *idempotencyKey = [self _generateUUID];

    /* Send to gateway with stream handler */
    [_gateway sendMessage:text
               sessionKey:sessionKey
                 thinking:nil
              attachments:nil
           idempotencyKey:idempotencyKey
             streamBlock:^(OCGatewayChatEvent *event) {
                 assistantMsg.runId = event.runId;
                 [_activeStreams setObject:assistantMsg forKey:event.runId ?: @""];

                 if (event.state == OCGatewayChatStateDelta) {
                     [assistantMsg appendDelta:event.messageText];
                     dispatch_async(dispatch_get_main_queue(), ^{
                         [_delegate sessionManager:self
                          didUpdateStreamingMessage:assistantMsg
                                          inSession:_activeSession];
                     });
                 } else if (event.state == OCGatewayChatStateFinal) {
                     if (event.messageText) {
                         [assistantMsg.streamBuffer setString:event.messageText];
                     }
                     [assistantMsg finalizeStream];
                     assistantMsg.inputTokens = event.inputTokens;
                     assistantMsg.outputTokens = event.outputTokens;
                     assistantMsg.stopReason = event.stopReason;

                     [self persistMessage:assistantMsg sessionKey:sessionKey];
                     [_activeStreams removeObjectForKey:event.runId ?: @""];

                     dispatch_async(dispatch_get_main_queue(), ^{
                         [_delegate sessionManager:self didReceiveMessage:assistantMsg
                                         inSession:_activeSession];
                     });
                 } else {
                     assistantMsg.state = (event.state == OCGatewayChatStateAborted)
                         ? OCMessageStateAborted : OCMessageStateError;
                     [assistantMsg finalizeStream];
                     [_activeStreams removeObjectForKey:event.runId ?: @""];

                     dispatch_async(dispatch_get_main_queue(), ^{
                         [_delegate sessionManager:self didReceiveMessage:assistantMsg
                                         inSession:_activeSession];
                     });
                 }
             }
            completion:nil];

    /* Update session timestamps */
    _activeSession.lastActiveAt = [NSDate date];
    _activeSession.totalMessages++;
    [self _persistSession:_activeSession];
}

- (void)abortCurrentResponse {
    if (!_activeSession) return;

    for (NSString *runId in [_activeStreams allKeys]) {
        OCMessage *msg = [_activeStreams objectForKey:runId];
        [msg finalizeStream];
        msg.state = OCMessageStateAborted;
    }
    [_activeStreams removeAllObjects];

    [_gateway abortChat:_activeSession.sessionKey runId:nil];
}

- (void)handleChatEvent:(OCGatewayChatEvent *)event {
    /* Delegate stream blocks handle most of this, but this method
       can be called for events from other sessions. */
    if (!event.sessionKey) return;

    BOOL isActiveSession = [event.sessionKey isEqualToString:_activeSession.sessionKey];
    if (!isActiveSession) {
        /* Update badge or notification for background session */
        return;
    }
}

#pragma mark - History

- (void)loadMoreHistory {
    if (!_activeSession) return;

    NSUInteger currentCount = [_activeSession->_messages count];
    NSArray *older = [self loadMessages:_activeSession.sessionKey
                                  limit:_activeSession.messageWindowSize
                                 offset:currentCount];

    if ([older count] > 0) {
        NSIndexSet *indices = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [older count])];
        [_activeSession->_messages insertObjects:older atIndexes:indices];

        dispatch_async(dispatch_get_main_queue(), ^{
            [_delegate sessionManager:self didUpdateSession:_activeSession];
        });
    }
}

#pragma mark - Persistence

- (void)persistMessage:(OCMessage *)message sessionKey:(NSString *)sessionKey {
    [_store execute:@"INSERT OR REPLACE INTO messages "
     @"(id, session_key, role, content, thinking, timestamp, "
     @"input_tokens, output_tokens, stop_reason, run_id) "
     @"VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
             params:@[
                 message.messageId,
                 sessionKey,
                 @(message.role),
                 message.content ?: [NSNull null],
                 message.thinking ?: [NSNull null],
                 @([message.timestamp timeIntervalSince1970]),
                 @(message.inputTokens),
                 @(message.outputTokens),
                 message.stopReason ?: [NSNull null],
                 message.runId ?: [NSNull null]
             ]
             error:nil];

    [_store execute:@"UPDATE sessions SET total_messages = total_messages + 1, "
     @"last_active_at = ? WHERE key = ?"
             params:@[@([[NSDate date] timeIntervalSince1970]), sessionKey]
             error:nil];
}

- (NSArray *)loadMessages:(NSString *)sessionKey
                    limit:(NSUInteger)limit
                   offset:(NSUInteger)offset {
    NSMutableArray *messages = [NSMutableArray arrayWithCapacity:limit];

    [_store query:@"SELECT * FROM messages WHERE session_key = ? "
     @"ORDER BY timestamp DESC LIMIT ? OFFSET ?"
           params:@[sessionKey, @(limit), @(offset)]
        enumerate:^(OCStoreRow *row, BOOL *stop) {
            OCMessage *msg = [[OCMessage alloc] init];
            msg.messageId = [row stringForColumn:@"id"];
            msg.role = (OCMessageRole)[row integerForColumn:@"role"];
            msg.content = [row stringForColumn:@"content"];
            msg.thinking = [row stringForColumn:@"thinking"];
            msg.timestamp = [NSDate dateWithTimeIntervalSince1970:
                             [row doubleForColumn:@"timestamp"]];
            msg.inputTokens = [row integerForColumn:@"input_tokens"];
            msg.outputTokens = [row integerForColumn:@"output_tokens"];
            msg.stopReason = [row stringForColumn:@"stop_reason"];
            msg.runId = [row stringForColumn:@"run_id"];
            [messages addObject:msg];
            [msg release];
        }
        error:nil];

    /* Reverse to chronological order */
    return [[messages reverseObjectEnumerator] allObjects];
}

- (void)_persistSession:(OCChatSession *)session {
    [_store execute:@"INSERT OR REPLACE INTO sessions "
     @"(key, display_name, created_at, last_active_at, total_messages) "
     @"VALUES (?, ?, ?, ?, ?)"
             params:@[
                 session.sessionKey,
                 session.displayName ?: [NSNull null],
                 @([session.createdAt timeIntervalSince1970]),
                 @([session.lastActiveAt timeIntervalSince1970]),
                 @(session.totalMessages)
             ]
             error:nil];
}

#pragma mark - Memory Management

- (void)trimMessageWindows {
    for (OCChatSession *session in _sessions) {
        if (session == _activeSession) continue;
        [session->_messages removeAllObjects];
    }

    /* Trim active session to window */
    if (_activeSession && [_activeSession->_messages count] > _activeSession.messageWindowSize) {
        NSUInteger excess = [_activeSession->_messages count] - _activeSession.messageWindowSize;
        [_activeSession->_messages removeObjectsInRange:NSMakeRange(0, excess)];
    }
}

- (NSUInteger)estimatedMemoryUsage {
    NSUInteger total = 0;
    for (OCChatSession *session in _sessions) {
        total += 128; /* session overhead */
        for (OCMessage *msg in session->_messages) {
            total += [msg estimatedMemoryCost];
        }
    }
    return total;
}

#pragma mark - Utilities

- (NSString *)_generateUUID {
    CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
    NSString *str = (NSString *)CFUUIDCreateString(kCFAllocatorDefault, uuid);
    CFRelease(uuid);
    return [str autorelease];
}

@end
