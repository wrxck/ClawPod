/*
 * TLSClient.m
 * LegacyPodClaw - TLS 1.2 HTTPS Client Implementation
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

        /* Read response — inline chunked transfer-encoding decoder.
         * For non-chunked: pass raw body through.
         * For chunked: strip chunk framing, deliver clean data.
         * Both modes deliver onChunk callbacks in real-time for SSE. */
        NSMutableData *responseData = [NSMutableData dataWithCapacity:8192];
        char readBuf[4096];
        BOOL headersDone = NO;
        BOOL isChunked = NO;
        NSInteger statusCode = 0;
        NSMutableData *headerBuf = [NSMutableData dataWithCapacity:2048];

        /* Chunked decoder state */
        NSMutableData *chunkBuf = nil;   /* accumulates raw chunked data between reads */
        unsigned long chunkRemain = 0;   /* bytes remaining in current chunk */
        BOOL needChunkSize = YES;        /* waiting for next chunk size line */

        while (1) {
            int bytesRead = wolfSSL_read(ssl, readBuf, sizeof(readBuf));
            if (bytesRead <= 0) break;

            if (!headersDone) {
                [headerBuf appendBytes:readBuf length:bytesRead];
                const uint8_t *hbytes = (const uint8_t *)[headerBuf bytes];
                NSUInteger hlen = [headerBuf length];
                for (NSUInteger i = 0; i + 3 < hlen; i++) {
                    if (hbytes[i] == '\r' && hbytes[i+1] == '\n' &&
                        hbytes[i+2] == '\r' && hbytes[i+3] == '\n') {
                        headersDone = YES;
                        NSString *headerStr = [[NSString alloc] initWithBytes:hbytes
                            length:i encoding:NSUTF8StringEncoding];
                        if ([headerStr length] > 12) {
                            statusCode = [[headerStr substringWithRange:NSMakeRange(9, 3)] integerValue];
                        }
                        NSString *lcHeaders = [headerStr lowercaseString];
                        isChunked = [lcHeaders rangeOfString:@"transfer-encoding: chunked"].location != NSNotFound;
                        NSLog(@"[TLSClient] %@ status=%ld chunked=%d bodyAfterHeaders=%lu",
                            host, (long)statusCode, isChunked, (unsigned long)(hlen - i - 4));
                        [headerStr release];
                        /* Remaining data after header boundary */
                        NSUInteger bodyStart = i + 4;
                        if (bodyStart < hlen) {
                            NSData *first = [NSData dataWithBytes:hbytes + bodyStart length:hlen - bodyStart];
                            if (isChunked) {
                                chunkBuf = [NSMutableData dataWithData:first];
                            } else {
                                [responseData appendData:first];
                                if (onChunk) {
                                    dispatch_async(dispatch_get_main_queue(), ^{ onChunk(first); });
                                }
                            }
                        } else if (isChunked) {
                            chunkBuf = [NSMutableData dataWithCapacity:4096];
                        }
                        break;
                    }
                }
                continue;
            }

            /* Body data */
            if (!isChunked) {
                NSData *chunk = [NSData dataWithBytes:readBuf length:bytesRead];
                [responseData appendData:chunk];
                if (onChunk) {
                    dispatch_async(dispatch_get_main_queue(), ^{ onChunk(chunk); });
                }
            } else {
                /* Feed into chunked decoder */
                [chunkBuf appendBytes:readBuf length:bytesRead];

                /* Process as many complete chunks as possible */
                BOOL done = NO;
                while (!done && [chunkBuf length] > 0) {
                    const uint8_t *cb = (const uint8_t *)[chunkBuf bytes];
                    NSUInteger cbLen = [chunkBuf length];

                    if (needChunkSize) {
                        /* Look for \r\n to get chunk size line */
                        NSUInteger crlfPos = NSNotFound;
                        for (NSUInteger j = 0; j + 1 < cbLen; j++) {
                            if (cb[j] == '\r' && cb[j+1] == '\n') {
                                crlfPos = j; break;
                            }
                        }
                        if (crlfPos == NSNotFound) break; /* need more data */

                        char hexBuf[16];
                        NSUInteger hexLen = MIN(crlfPos, 15);
                        memcpy(hexBuf, cb, hexLen);
                        hexBuf[hexLen] = '\0';
                        char *semi = strchr(hexBuf, ';');
                        if (semi) *semi = '\0';
                        chunkRemain = strtoul(hexBuf, NULL, 16);

                        /* Consume the size line + \r\n */
                        [chunkBuf replaceBytesInRange:NSMakeRange(0, crlfPos + 2) withBytes:NULL length:0];

                        if (chunkRemain == 0) { done = YES; break; } /* final chunk */
                        needChunkSize = NO;
                    } else {
                        /* Read chunk data */
                        NSUInteger avail = MIN(chunkRemain, [chunkBuf length]);
                        if (avail == 0) break;

                        NSData *decoded = [NSData dataWithBytes:[chunkBuf bytes] length:avail];
                        [responseData appendData:decoded];
                        if (onChunk) {
                            dispatch_async(dispatch_get_main_queue(), ^{ onChunk(decoded); });
                        }
                        [chunkBuf replaceBytesInRange:NSMakeRange(0, avail) withBytes:NULL length:0];
                        chunkRemain -= avail;

                        if (chunkRemain == 0) {
                            /* Consume trailing \r\n */
                            if ([chunkBuf length] >= 2) {
                                const uint8_t *p = (const uint8_t *)[chunkBuf bytes];
                                if (p[0] == '\r' && p[1] == '\n') {
                                    [chunkBuf replaceBytesInRange:NSMakeRange(0, 2) withBytes:NULL length:0];
                                }
                            }
                            needChunkSize = YES;
                        }
                    }
                }
            }
        }

        /* Save raw response for debugging */
        NSString *debugStr = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
        if (debugStr) {
            [debugStr writeToFile:@"/tmp/clawpod-last-response.txt" atomically:YES
                         encoding:NSUTF8StringEncoding error:nil];
            [debugStr release];
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
