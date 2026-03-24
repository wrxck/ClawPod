/*
 * TLSClient.m
 * ClawPod - TLS 1.2 HTTPS Client Implementation
 *
 * Uses wolfSSL for TLS 1.2 on iOS 6.
 * All network I/O on background queue, callbacks on main queue.
 */

#import "TLSClient.h"
#import <sys/socket.h>
#import <netdb.h>
#import <arpa/inet.h>

/* wolfSSL headers */
#include <wolfssl/ssl.h>

static BOOL _wolfSSLInitialized = NO;

static void _ensureWolfSSLInit(void) {
    if (!_wolfSSLInitialized) {
        wolfSSL_Init();
        _wolfSSLInitialized = YES;
    }
}

@implementation CPTLSClient

+ (void)request:(NSString *)urlString method:(NSString *)method
        headers:(NSDictionary *)headers body:(NSData *)body
     completion:(CPHTTPSCompletion)completion {

    [self streamRequest:urlString method:method headers:headers body:body
                onChunk:nil completion:completion];
}

+ (void)streamRequest:(NSString *)urlString method:(NSString *)method
              headers:(NSDictionary *)headers body:(NSData *)body
              onChunk:(CPHTTPSStreamChunk)onChunk
           completion:(CPHTTPSCompletion)completion {

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        _ensureWolfSSLInit();

        /* Parse URL */
        NSURL *url = [NSURL URLWithString:urlString];
        NSString *host = [url host];
        NSString *path = [url path] ?: @"/";
        NSString *query = [url query];
        if (query) path = [NSString stringWithFormat:@"%@?%@", path, query];
        int port = [[url port] intValue] ?: 443;

        /* DNS resolve */
        struct addrinfo hints, *res;
        memset(&hints, 0, sizeof(hints));
        hints.ai_family = AF_INET;
        hints.ai_socktype = SOCK_STREAM;

        char portStr[8];
        snprintf(portStr, sizeof(portStr), "%d", port);

        int gaiErr = getaddrinfo([host UTF8String], portStr, &hints, &res);
        if (gaiErr != 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, 0, [NSError errorWithDomain:@"CPTLSClient" code:-1
                    userInfo:@{NSLocalizedDescriptionKey:
                        [NSString stringWithFormat:@"DNS failed: %s", gai_strerror(gaiErr)]}]);
            });
            return;
        }

        /* Create socket */
        int sock = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
        if (sock < 0) {
            freeaddrinfo(res);
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, 0, [NSError errorWithDomain:@"CPTLSClient" code:-2
                    userInfo:@{NSLocalizedDescriptionKey: @"Socket creation failed"}]);
            });
            return;
        }

        /* Connect */
        if (connect(sock, res->ai_addr, res->ai_addrlen) != 0) {
            close(sock);
            freeaddrinfo(res);
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, 0, [NSError errorWithDomain:@"CPTLSClient" code:-3
                    userInfo:@{NSLocalizedDescriptionKey: @"TCP connect failed"}]);
            });
            return;
        }
        freeaddrinfo(res);

        /* wolfSSL context */
        WOLFSSL_CTX *ctx = wolfSSL_CTX_new(wolfTLSv1_2_client_method());
        if (!ctx) {
            close(sock);
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, 0, [NSError errorWithDomain:@"CPTLSClient" code:-4
                    userInfo:@{NSLocalizedDescriptionKey: @"wolfSSL CTX creation failed"}]);
            });
            return;
        }

        /* Don't verify server cert for now (iOS 6 doesn't have updated CA bundle)
           TODO: bundle CA certs and enable verification */
        wolfSSL_CTX_set_verify(ctx, SSL_VERIFY_NONE, NULL);

        WOLFSSL *ssl = wolfSSL_new(ctx);
        if (!ssl) {
            wolfSSL_CTX_free(ctx);
            close(sock);
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, 0, [NSError errorWithDomain:@"CPTLSClient" code:-5
                    userInfo:@{NSLocalizedDescriptionKey: @"wolfSSL session creation failed"}]);
            });
            return;
        }

        wolfSSL_set_fd(ssl, sock);

        /* SNI */
        wolfSSL_UseSNI(ssl, WOLFSSL_SNI_HOST_NAME,
                        [host UTF8String], (unsigned short)[host length]);

        /* TLS handshake */
        int ret = wolfSSL_connect(ssl);
        if (ret != SSL_SUCCESS) {
            int err = wolfSSL_get_error(ssl, ret);
            char errBuf[256];
            wolfSSL_ERR_error_string(err, errBuf);
            NSString *errStr = [NSString stringWithFormat:@"TLS handshake failed: %s", errBuf];
            wolfSSL_free(ssl);
            wolfSSL_CTX_free(ctx);
            close(sock);
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, 0, [NSError errorWithDomain:@"CPTLSClient" code:-6
                    userInfo:@{NSLocalizedDescriptionKey: errStr}]);
            });
            return;
        }

        /* Build HTTP request */
        NSMutableString *httpReq = [NSMutableString stringWithCapacity:512];
        [httpReq appendFormat:@"%@ %@ HTTP/1.1\r\n", method ?: @"GET", path];
        [httpReq appendFormat:@"Host: %@\r\n", host];
        [httpReq appendString:@"Connection: close\r\n"];

        if (body) {
            [httpReq appendFormat:@"Content-Length: %lu\r\n", (unsigned long)[body length]];
        }

        for (NSString *key in headers) {
            [httpReq appendFormat:@"%@: %@\r\n", key, [headers objectForKey:key]];
        }
        [httpReq appendString:@"\r\n"];

        /* Send request */
        NSData *reqData = [httpReq dataUsingEncoding:NSUTF8StringEncoding];
        wolfSSL_write(ssl, [reqData bytes], (int)[reqData length]);
        if (body) {
            wolfSSL_write(ssl, [body bytes], (int)[body length]);
        }

        /* Read response */
        NSMutableData *responseData = [NSMutableData dataWithCapacity:4096];
        char readBuf[4096];
        BOOL headersDone = NO;
        NSInteger statusCode = 0;
        NSMutableData *headerBuf = [NSMutableData dataWithCapacity:2048];

        while (1) {
            int bytesRead = wolfSSL_read(ssl, readBuf, sizeof(readBuf));
            if (bytesRead <= 0) break;

            if (!headersDone) {
                [headerBuf appendBytes:readBuf length:bytesRead];

                /* Look for \r\n\r\n */
                const uint8_t *bytes = [headerBuf bytes];
                NSUInteger len = [headerBuf length];
                for (NSUInteger i = 0; i + 3 < len; i++) {
                    if (bytes[i] == '\r' && bytes[i+1] == '\n' &&
                        bytes[i+2] == '\r' && bytes[i+3] == '\n') {
                        headersDone = YES;

                        /* Parse status code */
                        NSString *headerStr = [[NSString alloc] initWithBytes:bytes
                            length:i encoding:NSUTF8StringEncoding];
                        if ([headerStr length] > 12) {
                            NSString *statusStr = [headerStr substringWithRange:NSMakeRange(9, 3)];
                            statusCode = [statusStr integerValue];
                        }
                        [headerStr release];

                        /* Remaining data after headers is body */
                        NSUInteger bodyStart = i + 4;
                        if (bodyStart < len) {
                            NSData *bodyChunk = [NSData dataWithBytes:bytes + bodyStart
                                                               length:len - bodyStart];
                            [responseData appendData:bodyChunk];
                            if (onChunk) {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    onChunk(bodyChunk);
                                });
                            }
                        }
                        break;
                    }
                }
            } else {
                NSData *chunk = [NSData dataWithBytes:readBuf length:bytesRead];
                [responseData appendData:chunk];
                if (onChunk) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        onChunk(chunk);
                    });
                }
            }
        }

        /* Cleanup */
        wolfSSL_shutdown(ssl);
        wolfSSL_free(ssl);
        wolfSSL_CTX_free(ctx);
        close(sock);

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(responseData, statusCode, nil);
        });
    });
}

+ (void)postJSON:(NSString *)urlString headers:(NSDictionary *)headers
            body:(NSDictionary *)jsonBody
      completion:(void(^)(NSDictionary *, NSError *))completion {

    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:jsonBody options:0 error:nil];

    NSMutableDictionary *hdrs = [NSMutableDictionary dictionaryWithDictionary:headers ?: @{}];
    [hdrs setObject:@"application/json" forKey:@"Content-Type"];

    [self request:urlString method:@"POST" headers:hdrs body:bodyData
       completion:^(NSData *data, NSInteger statusCode, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        completion(json, nil);
    }];
}

@end
