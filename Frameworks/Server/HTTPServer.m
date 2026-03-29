/*
 * OCHTTPServer.m
 * ClawPod - HTTP Server Implementation
 *
 * Uses CFSocket for non-blocking accept, NSStream for I/O.
 * Parses HTTP/1.1 requests, routes to handlers, supports WS upgrade.
 */

#import "HTTPServer.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>

static const NSUInteger kDefaultMaxConnections = 32;
static const NSUInteger kDefaultMaxBodySize = 4 * 1024 * 1024;
static const NSTimeInterval kDefaultRequestTimeout = 30.0;
static const NSUInteger kReadBufferSize = 4096;

#pragma mark - OCHTTPRequest

@implementation OCHTTPRequest

- (void)dealloc {
    [_method release]; [_path release]; [_query release];
    [_headers release]; [_body release]; [_remoteAddress release];
    [super dealloc];
}

- (NSString *)headerValue:(NSString *)name {
    /* Case-insensitive header lookup */
    for (NSString *key in _headers) {
        if ([key caseInsensitiveCompare:name] == NSOrderedSame) {
            return [_headers objectForKey:key];
        }
    }
    return nil;
}

- (NSDictionary *)queryParams {
    if (!_query || [_query length] == 0) return @{};
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    for (NSString *pair in [_query componentsSeparatedByString:@"&"]) {
        NSArray *kv = [pair componentsSeparatedByString:@"="];
        if ([kv count] >= 2) {
            NSString *key = [[kv objectAtIndex:0]
                stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            NSString *val = [[kv objectAtIndex:1]
                stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            if (key && val) [params setObject:val forKey:key];
        }
    }
    return params;
}

- (NSDictionary *)jsonBody {
    if (!_body || [_body length] == 0) return nil;
    return [NSJSONSerialization JSONObjectWithData:_body options:0 error:nil];
}

- (NSString *)bearerToken {
    NSString *auth = [self headerValue:@"Authorization"];
    if (auth && [auth hasPrefix:@"Bearer "]) {
        return [auth substringFromIndex:7];
    }
    return nil;
}

- (BOOL)isWebSocketUpgrade {
    NSString *upgrade = [self headerValue:@"Upgrade"];
    NSString *connection = [self headerValue:@"Connection"];
    return (upgrade && [upgrade caseInsensitiveCompare:@"websocket"] == NSOrderedSame &&
            connection && [connection rangeOfString:@"Upgrade" options:NSCaseInsensitiveSearch].location != NSNotFound);
}

@end

#pragma mark - OCHTTPResponse

@implementation OCHTTPResponse

- (instancetype)init {
    if ((self = [super init])) {
        _statusCode = 200;
        _headers = [[NSMutableDictionary alloc] initWithCapacity:4];
        [_headers setObject:@"LegacyPodClaw/0.3.0" forKey:@"Server"];
        [_headers setObject:@"close" forKey:@"Connection"];
    }
    return self;
}

- (void)dealloc {
    [_headers release]; [_body release];
    [super dealloc];
}

+ (OCHTTPResponse *)responseWithStatus:(NSInteger)status {
    OCHTTPResponse *r = [[[OCHTTPResponse alloc] init] autorelease];
    r.statusCode = status;
    return r;
}

+ (OCHTTPResponse *)jsonResponse:(id)object {
    return [self jsonResponse:object status:200];
}

+ (OCHTTPResponse *)jsonResponse:(id)object status:(NSInteger)status {
    OCHTTPResponse *r = [[[OCHTTPResponse alloc] init] autorelease];
    r.statusCode = status;
    [r.headers setObject:@"application/json" forKey:@"Content-Type"];
    r.body = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    return r;
}

+ (OCHTTPResponse *)textResponse:(NSString *)text {
    OCHTTPResponse *r = [[[OCHTTPResponse alloc] init] autorelease];
    [r.headers setObject:@"text/plain; charset=utf-8" forKey:@"Content-Type"];
    r.body = [text dataUsingEncoding:NSUTF8StringEncoding];
    return r;
}

+ (OCHTTPResponse *)errorResponse:(NSInteger)status message:(NSString *)message {
    return [self jsonResponse:@{@"ok": @NO, @"error": message} status:status];
}

- (NSData *)serializedHTTPResponse {
    NSString *statusText = [self _statusText:_statusCode];
    NSMutableString *header = [NSMutableString stringWithCapacity:256];
    [header appendFormat:@"HTTP/1.1 %ld %@\r\n", (long)_statusCode, statusText];

    if (_body) {
        [_headers setObject:[NSString stringWithFormat:@"%lu", (unsigned long)[_body length]]
                     forKey:@"Content-Length"];
    }

    for (NSString *key in _headers) {
        [header appendFormat:@"%@: %@\r\n", key, [_headers objectForKey:key]];
    }
    [header appendString:@"\r\n"];

    NSMutableData *data = [NSMutableData dataWithData:[header dataUsingEncoding:NSUTF8StringEncoding]];
    if (_body) [data appendData:_body];
    return data;
}

- (NSString *)_statusText:(NSInteger)code {
    switch (code) {
        case 200: return @"OK";
        case 201: return @"Created";
        case 204: return @"No Content";
        case 400: return @"Bad Request";
        case 401: return @"Unauthorized";
        case 403: return @"Forbidden";
        case 404: return @"Not Found";
        case 405: return @"Method Not Allowed";
        case 413: return @"Payload Too Large";
        case 500: return @"Internal Server Error";
        case 503: return @"Service Unavailable";
        default:  return @"Unknown";
    }
}

@end

#pragma mark - Route Entry

@interface _OCRouteEntry : NSObject {
    @public
    NSString *method;
    NSString *path;
    OCHTTPHandler handler;
    BOOL isPrefix; /* path ends with * */
}
@end

@implementation _OCRouteEntry
- (void)dealloc {
    [method release]; [path release]; [handler release];
    [super dealloc];
}
@end

#pragma mark - Client Connection

@interface _OCHTTPConnection : NSObject <NSStreamDelegate> {
    @public
    NSInputStream *inputStream;
    NSOutputStream *outputStream;
    CFSocketNativeHandle socket;
    NSString *remoteAddress;
    uint16_t remotePort;

    NSMutableData *readBuffer;
    BOOL headersParsed;
    NSUInteger contentLength;
    NSUInteger bodyBytesRead;
    OCHTTPRequest *request;

    OCHTTPServer *server; /* weak - not retained */
    NSTimer *timeoutTimer;
}
@end

@implementation _OCHTTPConnection

- (void)dealloc {
    [inputStream setDelegate:nil]; [outputStream setDelegate:nil];
    [inputStream close]; [outputStream close];
    [inputStream release]; [outputStream release];
    [remoteAddress release]; [readBuffer release]; [request release];
    [timeoutTimer invalidate];
    [super dealloc];
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode {
    if (aStream == inputStream && eventCode == NSStreamEventHasBytesAvailable) {
        [server _readDataFromConnection:self];
    } else if (eventCode == NSStreamEventErrorOccurred || eventCode == NSStreamEventEndEncountered) {
        [server _closeConnection:self];
    }
}

@end

#pragma mark - OCHTTPServer

@interface OCHTTPServer () {
    CFSocketRef _listenSocket;
    NSMutableArray *_routes;
    NSMutableSet *_connections;
    OCWSUpgradeHandler _wsUpgradeHandler;
    NSString *_staticDir;
    NSString *_staticURLPath;
}
@end

/* Accept callback */
static void OCHTTPServerAcceptCallback(CFSocketRef s, CFSocketCallBackType type,
                                        CFDataRef address, const void *data, void *info);

@implementation OCHTTPServer

- (instancetype)init {
    if ((self = [super init])) {
        _port = 18789;
        _bindAddress = [@"0.0.0.0" retain];
        _maxConnections = kDefaultMaxConnections;
        _maxBodySize = kDefaultMaxBodySize;
        _requestTimeout = kDefaultRequestTimeout;
        _routes = [[NSMutableArray alloc] initWithCapacity:16];
        _connections = [[NSMutableSet alloc] initWithCapacity:16];
    }
    return self;
}

- (void)dealloc {
    [self stop];
    [_bindAddress release]; [_routes release]; [_connections release];
    [_wsUpgradeHandler release]; [_staticDir release]; [_staticURLPath release];
    [super dealloc];
}

#pragma mark - Start/Stop

- (BOOL)start:(NSError **)error {
    if (_isRunning) return YES;

    /* Create socket */
    CFSocketContext ctx = {0, (__bridge void *)self, NULL, NULL, NULL};
    _listenSocket = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP,
                                    kCFSocketAcceptCallBack, OCHTTPServerAcceptCallback, &ctx);

    if (!_listenSocket) {
        if (error) *error = [NSError errorWithDomain:@"OCHTTPServer" code:-1
                                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to create socket"}];
        return NO;
    }

    /* Allow address reuse */
    int yes = 1;
    setsockopt(CFSocketGetNative(_listenSocket), SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));

    /* Bind */
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(_port);
    addr.sin_addr.s_addr = inet_addr([_bindAddress UTF8String]);

    NSData *addrData = [NSData dataWithBytes:&addr length:sizeof(addr)];
    CFSocketError sockErr = CFSocketSetAddress(_listenSocket, (__bridge CFDataRef)addrData);

    if (sockErr != kCFSocketSuccess) {
        CFRelease(_listenSocket); _listenSocket = NULL;
        if (error) *error = [NSError errorWithDomain:@"OCHTTPServer" code:-2
                                            userInfo:@{NSLocalizedDescriptionKey:
            [NSString stringWithFormat:@"Failed to bind to %@:%d", _bindAddress, _port]}];
        return NO;
    }

    /* Schedule on run loop */
    CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, _listenSocket, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
    CFRelease(source);

    _isRunning = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([_delegate respondsToSelector:@selector(httpServerDidStart:port:)]) {
            [_delegate httpServerDidStart:self port:_port];
        }
    });

    return YES;
}

- (void)stop {
    if (!_isRunning) return;

    if (_listenSocket) {
        CFSocketInvalidate(_listenSocket);
        CFRelease(_listenSocket);
        _listenSocket = NULL;
    }

    /* Close all connections */
    for (_OCHTTPConnection *conn in [_connections allObjects]) {
        [self _closeConnection:conn];
    }

    _isRunning = NO;

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([_delegate respondsToSelector:@selector(httpServerDidStop:)]) {
            [_delegate httpServerDidStop:self];
        }
    });
}

#pragma mark - Routing

- (void)get:(NSString *)path handler:(OCHTTPHandler)handler {
    [self route:@"GET" path:path handler:handler];
}

- (void)post:(NSString *)path handler:(OCHTTPHandler)handler {
    [self route:@"POST" path:path handler:handler];
}

- (void)route:(NSString *)method path:(NSString *)path handler:(OCHTTPHandler)handler {
    _OCRouteEntry *entry = [[_OCRouteEntry alloc] init];
    entry->method = [method retain];
    entry->isPrefix = [path hasSuffix:@"*"];
    entry->path = [entry->isPrefix ? [path substringToIndex:[path length] - 1] : path retain];
    entry->handler = [handler copy];
    [_routes addObject:entry];
    [entry release];
}

- (void)onWebSocketUpgrade:(OCWSUpgradeHandler)handler {
    [_wsUpgradeHandler release];
    _wsUpgradeHandler = [handler copy];
}

- (void)serveStaticFiles:(NSString *)directory atPath:(NSString *)urlPath {
    [_staticDir release]; _staticDir = [directory copy];
    [_staticURLPath release]; _staticURLPath = [urlPath copy];
}

#pragma mark - Accept

- (void)_acceptConnection:(CFSocketNativeHandle)nativeSocket {
    if ([_connections count] >= _maxConnections) {
        close(nativeSocket);
        return;
    }

    /* Get remote address */
    struct sockaddr_in peerAddr;
    socklen_t peerLen = sizeof(peerAddr);
    getpeername(nativeSocket, (struct sockaddr *)&peerAddr, &peerLen);
    char addrBuf[INET_ADDRSTRLEN];
    inet_ntop(AF_INET, &peerAddr.sin_addr, addrBuf, sizeof(addrBuf));

    /* Create streams */
    CFReadStreamRef readStream;
    CFWriteStreamRef writeStream;
    CFStreamCreatePairWithSocket(kCFAllocatorDefault, nativeSocket, &readStream, &writeStream);

    if (!readStream || !writeStream) {
        if (readStream) CFRelease(readStream);
        if (writeStream) CFRelease(writeStream);
        close(nativeSocket);
        return;
    }

    /* Prevent socket close when streams released */
    CFReadStreamSetProperty(readStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
    CFWriteStreamSetProperty(writeStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);

    _OCHTTPConnection *conn = [[_OCHTTPConnection alloc] init];
    conn->inputStream = (NSInputStream *)readStream;
    conn->outputStream = (NSOutputStream *)writeStream;
    conn->socket = nativeSocket;
    conn->remoteAddress = [[NSString stringWithUTF8String:addrBuf] retain];
    conn->remotePort = ntohs(peerAddr.sin_port);
    conn->readBuffer = [[NSMutableData alloc] initWithCapacity:kReadBufferSize];
    conn->headersParsed = NO;
    conn->server = self;

    [conn->inputStream setDelegate:conn];
    [conn->outputStream setDelegate:conn];
    [conn->inputStream scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    [conn->outputStream scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    [conn->inputStream open];
    [conn->outputStream open];

    /* Timeout */
    conn->timeoutTimer = [NSTimer scheduledTimerWithTimeInterval:_requestTimeout
                                                          target:self
                                                        selector:@selector(_connectionTimeout:)
                                                        userInfo:conn
                                                         repeats:NO];

    [_connections addObject:conn];
    [conn release];
}

#pragma mark - Read/Parse

- (void)_readDataFromConnection:(_OCHTTPConnection *)conn {
    uint8_t buf[4096];
    while ([conn->inputStream hasBytesAvailable]) {
        NSInteger bytesRead = [conn->inputStream read:buf maxLength:kReadBufferSize];
        if (bytesRead <= 0) break;
        [conn->readBuffer appendBytes:buf length:bytesRead];
    }

    if (!conn->headersParsed) {
        [self _tryParseHeaders:conn];
    } else if (conn->contentLength > 0) {
        [self _tryReadBody:conn];
    }
}

- (void)_tryParseHeaders:(_OCHTTPConnection *)conn {
    const uint8_t *bytes = [conn->readBuffer bytes];
    NSUInteger length = [conn->readBuffer length];

    /* Find \r\n\r\n */
    NSUInteger headerEnd = 0;
    for (NSUInteger i = 0; i + 3 < length; i++) {
        if (bytes[i] == '\r' && bytes[i+1] == '\n' && bytes[i+2] == '\r' && bytes[i+3] == '\n') {
            headerEnd = i + 4;
            break;
        }
    }
    if (headerEnd == 0) return; /* Headers not complete yet */

    NSString *headerStr = [[NSString alloc] initWithBytes:bytes length:headerEnd encoding:NSUTF8StringEncoding];
    NSArray *lines = [headerStr componentsSeparatedByString:@"\r\n"];
    [headerStr release];

    if ([lines count] < 1) { [self _closeConnection:conn]; return; }

    /* Parse request line */
    NSArray *parts = [[lines objectAtIndex:0] componentsSeparatedByString:@" "];
    if ([parts count] < 2) { [self _closeConnection:conn]; return; }

    OCHTTPRequest *req = [[OCHTTPRequest alloc] init];
    req.method = [parts objectAtIndex:0];
    req.remoteAddress = conn->remoteAddress;
    req.remotePort = conn->remotePort;

    /* Parse path and query */
    NSString *uri = [parts objectAtIndex:1];
    NSRange qRange = [uri rangeOfString:@"?"];
    if (qRange.location != NSNotFound) {
        req.path = [uri substringToIndex:qRange.location];
        req.query = [uri substringFromIndex:qRange.location + 1];
    } else {
        req.path = uri;
    }

    /* Parse headers */
    NSMutableDictionary *hdrs = [NSMutableDictionary dictionaryWithCapacity:8];
    for (NSUInteger i = 1; i < [lines count]; i++) {
        NSString *line = [lines objectAtIndex:i];
        if ([line length] == 0) break;
        NSRange colonRange = [line rangeOfString:@": "];
        if (colonRange.location != NSNotFound) {
            NSString *key = [line substringToIndex:colonRange.location];
            NSString *val = [line substringFromIndex:colonRange.location + 2];
            [hdrs setObject:val forKey:key];
        }
    }
    req.headers = hdrs;

    conn->request = req;
    conn->headersParsed = YES;

    /* Content-Length */
    NSString *clStr = [req headerValue:@"Content-Length"];
    conn->contentLength = clStr ? [clStr integerValue] : 0;

    if (conn->contentLength > _maxBodySize) {
        [self _sendResponse:[OCHTTPResponse errorResponse:413 message:@"Payload too large"]
               toConnection:conn];
        return;
    }

    /* Remove headers from buffer, keep body data */
    NSData *remaining = nil;
    if (headerEnd < length) {
        remaining = [NSData dataWithBytes:bytes + headerEnd length:length - headerEnd];
    }
    [conn->readBuffer setLength:0];
    if (remaining) [conn->readBuffer appendData:remaining];
    conn->bodyBytesRead = [conn->readBuffer length];

    if (conn->contentLength == 0 || conn->bodyBytesRead >= conn->contentLength) {
        req.body = conn->contentLength > 0 ? [[conn->readBuffer copy] autorelease] : nil;
        [self _dispatchRequest:conn];
    }
}

- (void)_tryReadBody:(_OCHTTPConnection *)conn {
    conn->bodyBytesRead = [conn->readBuffer length];
    if (conn->bodyBytesRead >= conn->contentLength) {
        conn->request.body = [[conn->readBuffer subdataWithRange:
            NSMakeRange(0, conn->contentLength)] retain];
        [self _dispatchRequest:conn];
    }
}

#pragma mark - Dispatch

- (void)_dispatchRequest:(_OCHTTPConnection *)conn {
    [conn->timeoutTimer invalidate];
    conn->timeoutTimer = nil;

    OCHTTPRequest *req = conn->request;

    /* WebSocket upgrade? */
    if ([req isWebSocketUpgrade] && _wsUpgradeHandler) {
        /* Remove streams from runloop - WS server takes over */
        [conn->inputStream removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        [conn->outputStream removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        [conn->inputStream setDelegate:nil];
        [conn->outputStream setDelegate:nil];

        _wsUpgradeHandler(req, conn->socket, conn->inputStream, conn->outputStream);

        /* Don't close - WS server owns the socket now */
        conn->inputStream = nil;
        conn->outputStream = nil;
        [_connections removeObject:conn];
        return;
    }

    /* Match route */
    for (_OCRouteEntry *route in _routes) {
        if (![route->method isEqualToString:req.method]) continue;

        BOOL match = NO;
        if (route->isPrefix) {
            match = [req.path hasPrefix:route->path];
        } else {
            match = [req.path isEqualToString:route->path];
        }

        if (match) {
            route->handler(req, ^(OCHTTPResponse *response) {
                [self _sendResponse:response toConnection:conn];
            });
            return;
        }
    }

    /* Static files? */
    if (_staticDir && _staticURLPath && [req.path hasPrefix:_staticURLPath]) {
        [self _serveStaticFile:req connection:conn];
        return;
    }

    /* 404 */
    [self _sendResponse:[OCHTTPResponse errorResponse:404 message:@"Not found"] toConnection:conn];
}

- (void)_serveStaticFile:(OCHTTPRequest *)req connection:(_OCHTTPConnection *)conn {
    NSString *relativePath = [req.path substringFromIndex:[_staticURLPath length]];
    if ([relativePath length] == 0 || [relativePath isEqualToString:@"/"]) {
        relativePath = @"/index.html";
    }
    NSString *filePath = [_staticDir stringByAppendingPathComponent:relativePath];

    /* Security: prevent path traversal */
    NSString *resolved = [filePath stringByStandardizingPath];
    if (![resolved hasPrefix:[_staticDir stringByStandardizingPath]]) {
        [self _sendResponse:[OCHTTPResponse errorResponse:403 message:@"Forbidden"] toConnection:conn];
        return;
    }

    NSData *fileData = [NSData dataWithContentsOfFile:resolved];
    if (!fileData) {
        [self _sendResponse:[OCHTTPResponse errorResponse:404 message:@"Not found"] toConnection:conn];
        return;
    }

    OCHTTPResponse *resp = [OCHTTPResponse responseWithStatus:200];
    resp.body = fileData;

    /* Content type from extension */
    NSString *ext = [[resolved pathExtension] lowercaseString];
    NSString *ct = @"application/octet-stream";
    if ([ext isEqualToString:@"html"]) ct = @"text/html; charset=utf-8";
    else if ([ext isEqualToString:@"js"]) ct = @"application/javascript";
    else if ([ext isEqualToString:@"css"]) ct = @"text/css";
    else if ([ext isEqualToString:@"json"]) ct = @"application/json";
    else if ([ext isEqualToString:@"png"]) ct = @"image/png";
    else if ([ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"]) ct = @"image/jpeg";
    [resp.headers setObject:ct forKey:@"Content-Type"];

    [self _sendResponse:resp toConnection:conn];
}

#pragma mark - Response

- (void)_sendResponse:(OCHTTPResponse *)response toConnection:(_OCHTTPConnection *)conn {
    NSData *data = [response serializedHTTPResponse];
    if (conn->outputStream && [conn->outputStream hasSpaceAvailable]) {
        [conn->outputStream write:[data bytes] maxLength:[data length]];
    }
    /* Close after response (HTTP/1.0 style for simplicity on constrained device) */
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{
        [self _closeConnection:conn];
    });
}

#pragma mark - Connection Management

- (void)_closeConnection:(_OCHTTPConnection *)conn {
    [conn->timeoutTimer invalidate];
    conn->timeoutTimer = nil;
    [conn->inputStream setDelegate:nil];
    [conn->outputStream setDelegate:nil];
    [conn->inputStream close];
    [conn->outputStream close];
    [_connections removeObject:conn];
}

- (void)_connectionTimeout:(NSTimer *)timer {
    _OCHTTPConnection *conn = [timer userInfo];
    [self _sendResponse:[OCHTTPResponse errorResponse:408 message:@"Request timeout"] toConnection:conn];
}

- (NSUInteger)activeConnections {
    return [_connections count];
}

@end

#pragma mark - Accept Callback

static void OCHTTPServerAcceptCallback(CFSocketRef s, CFSocketCallBackType type,
                                        CFDataRef address, const void *data, void *info) {
    OCHTTPServer *server = (__bridge OCHTTPServer *)info;
    if (type == kCFSocketAcceptCallBack && data) {
        CFSocketNativeHandle nativeSocket = *(CFSocketNativeHandle *)data;
        [server _acceptConnection:nativeSocket];
    }
}
