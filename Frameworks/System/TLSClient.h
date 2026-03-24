/*
 * TLSClient.h
 * ClawPod - TLS 1.2 HTTPS Client (wolfSSL)
 *
 * Provides HTTPS requests using wolfSSL for TLS 1.2 support
 * on iOS 6 devices where the system only supports TLS 1.0.
 * Used for all API calls to Anthropic, OpenAI, etc.
 */

#import <Foundation/Foundation.h>

typedef void(^CPHTTPSCompletion)(NSData *data, NSInteger statusCode, NSError *error);
typedef void(^CPHTTPSStreamChunk)(NSData *chunk);

@interface CPTLSClient : NSObject

/* Simple HTTPS request (non-streaming) */
+ (void)request:(NSString *)urlString
         method:(NSString *)method
        headers:(NSDictionary *)headers
           body:(NSData *)body
     completion:(CPHTTPSCompletion)completion;

/* Streaming HTTPS request (for SSE) */
+ (void)streamRequest:(NSString *)urlString
               method:(NSString *)method
              headers:(NSDictionary *)headers
                 body:(NSData *)body
              onChunk:(CPHTTPSStreamChunk)onChunk
           completion:(CPHTTPSCompletion)completion;

/* Convenience: POST JSON and get JSON back */
+ (void)postJSON:(NSString *)urlString
         headers:(NSDictionary *)headers
            body:(NSDictionary *)jsonBody
      completion:(void(^)(NSDictionary *json, NSError *error))completion;

@end
