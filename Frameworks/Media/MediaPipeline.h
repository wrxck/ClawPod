/*
 * OCMediaPipeline.h
 * LegacyPodClaw - Media Processing Pipeline
 *
 * Image ops, TTS, link understanding, audio transcription stubs.
 * Lightweight implementations suitable for 256MB RAM.
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#pragma mark - Image Operations

@interface OCImageOps : NSObject
/* Resize image to fit within maxDimension, preserving aspect ratio */
+ (UIImage *)resizeImage:(UIImage *)image maxDimension:(CGFloat)maxDim;
/* Compress to JPEG with quality (0.0-1.0) */
+ (NSData *)compressImage:(UIImage *)image quality:(CGFloat)quality;
/* Get image dimensions without loading full image */
+ (CGSize)imageSizeAtPath:(NSString *)path;
/* Convert between formats */
+ (NSData *)imageToPNG:(UIImage *)image;
+ (NSData *)imageToJPEG:(UIImage *)image quality:(CGFloat)quality;
@end

#pragma mark - TTS (Text-to-Speech)

typedef NS_ENUM(NSUInteger, OCTTSProvider) {
    OCTTSProviderSystem = 0,     // iOS system speech (AVSpeechSynthesizer - iOS 7+ only)
    OCTTSProviderElevenLabs,     // ElevenLabs API
    OCTTSProviderOpenAI          // OpenAI TTS API
};

@interface OCTTSService : NSObject
@property (nonatomic, assign) OCTTSProvider provider;
@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, copy) NSString *voiceId;
@property (nonatomic, copy) NSString *model;       // e.g., "eleven_monolingual_v1"

/* Synthesize text to audio data (PCM/MP3) */
- (void)synthesize:(NSString *)text
        completion:(void(^)(NSData *audioData, NSString *format, NSError *error))completion;
@end

#pragma mark - Link Understanding

@interface OCLinkUnderstanding : NSObject
/* Fetch URL and extract main content text */
+ (void)extractContentFromURL:(NSString *)urlString
                    completion:(void(^)(NSString *title, NSString *content, NSError *error))completion;
/* Extract OpenGraph metadata */
+ (void)fetchMetadata:(NSString *)urlString
           completion:(void(^)(NSDictionary *metadata, NSError *error))completion;
@end

#pragma mark - Audio Transcription (stub for API-based)

@interface OCTranscriptionService : NSObject
@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, copy) NSString *provider; // "openai" or "deepgram"

- (void)transcribe:(NSData *)audioData
            format:(NSString *)format
        completion:(void(^)(NSString *text, NSError *error))completion;
@end

#pragma mark - WebChat HTML Server

@interface OCWebChatServer : NSObject
/* Generate the complete WebChat HTML page that connects to the gateway */
+ (NSString *)webChatHTMLForGatewayHost:(NSString *)host port:(uint16_t)port;
/* Generate the Control UI dashboard HTML */
+ (NSString *)controlUIHTMLForGatewayHost:(NSString *)host port:(uint16_t)port;
@end
