/*
 * OCHTTPServer.h
 * ClawPod - Lightweight HTTP Server
 *
 * CFSocket-based HTTP/1.1 server for the gateway.
 * Handles request routing, WebSocket upgrades, and static file serving.
 * Designed for <5MB memory footprint on 256MB device.
 */

#import <Foundation/Foundation.h>
#import <CFNetwork/CFNetwork.h>

#pragma mark - HTTP Request

@interface OCHTTPRequest : NSObject
@property (nonatomic, copy) NSString *method;       // GET, POST, etc.
@property (nonatomic, copy) NSString *path;         // /health, /sessions/*, etc.
@property (nonatomic, copy) NSString *query;        // Raw query string
@property (nonatomic, copy) NSDictionary *headers;
@property (nonatomic, retain) NSData *body;
@property (nonatomic, copy) NSString *remoteAddress;
@property (nonatomic, assign) uint16_t remotePort;

/* Parsed helpers */
- (NSString *)headerValue:(NSString *)name;
- (NSDictionary *)queryParams;
- (NSDictionary *)jsonBody;
- (NSString *)bearerToken;
- (BOOL)isWebSocketUpgrade;
@end

#pragma mark - HTTP Response

@interface OCHTTPResponse : NSObject
@property (nonatomic, assign) NSInteger statusCode;
@property (nonatomic, retain) NSMutableDictionary *headers;
@property (nonatomic, retain) NSData *body;

+ (OCHTTPResponse *)responseWithStatus:(NSInteger)status;
+ (OCHTTPResponse *)jsonResponse:(id)object;
+ (OCHTTPResponse *)jsonResponse:(id)object status:(NSInteger)status;
+ (OCHTTPResponse *)textResponse:(NSString *)text;
+ (OCHTTPResponse *)errorResponse:(NSInteger)status message:(NSString *)message;

- (NSData *)serializedHTTPResponse;
@end

#pragma mark - Route Handler

typedef void(^OCHTTPHandler)(OCHTTPRequest *request, void(^respond)(OCHTTPResponse *));

/* WebSocket upgrade callback - returns the raw socket for the WS server */
typedef void(^OCWSUpgradeHandler)(OCHTTPRequest *request,
                                   CFSocketNativeHandle socket,
                                   NSInputStream *input,
                                   NSOutputStream *output);

#pragma mark - HTTP Server

@protocol OCHTTPServerDelegate <NSObject>
@optional
- (void)httpServerDidStart:(id)server port:(uint16_t)port;
- (void)httpServerDidStop:(id)server;
- (void)httpServer:(id)server didFailWithError:(NSError *)error;
- (void)httpServer:(id)server didAcceptConnection:(NSString *)remoteAddress;
@end

@interface OCHTTPServer : NSObject

@property (nonatomic, assign) id<OCHTTPServerDelegate> delegate;
@property (nonatomic, assign) uint16_t port;           // Default 18789
@property (nonatomic, copy) NSString *bindAddress;     // Default "0.0.0.0"
@property (nonatomic, readonly) BOOL isRunning;
@property (nonatomic, readonly) NSUInteger activeConnections;

/* Max concurrent connections (default 32 for memory conservation) */
@property (nonatomic, assign) NSUInteger maxConnections;

/* Max request body size (default 4MB) */
@property (nonatomic, assign) NSUInteger maxBodySize;

/* Request timeout (default 30s) */
@property (nonatomic, assign) NSTimeInterval requestTimeout;

- (BOOL)start:(NSError **)error;
- (void)stop;

/* Route registration */
- (void)get:(NSString *)path handler:(OCHTTPHandler)handler;
- (void)post:(NSString *)path handler:(OCHTTPHandler)handler;
- (void)route:(NSString *)method path:(NSString *)path handler:(OCHTTPHandler)handler;

/* WebSocket upgrade handler */
- (void)onWebSocketUpgrade:(OCWSUpgradeHandler)handler;

/* Serve static files from a directory */
- (void)serveStaticFiles:(NSString *)directory atPath:(NSString *)urlPath;

@end
