/*
 * OCVoiceService.h
 * ClawPod - Voice Input Service
 *
 * Uses AudioQueue for microphone input on iPod Touch 4.
 * Records audio, sends to gateway for transcription,
 * or uses the local agent directly.
 * Note: iPod Touch 4 has no built-in mic - requires headset.
 */

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

typedef NS_ENUM(NSUInteger, OCVoiceState) {
    OCVoiceStateIdle = 0,
    OCVoiceStateListening,
    OCVoiceStateProcessing
};

@protocol OCVoiceServiceDelegate <NSObject>
- (void)voiceServiceDidStartListening:(id)service;
- (void)voiceServiceDidStopListening:(id)service;
- (void)voiceService:(id)service didTranscribeText:(NSString *)text;
- (void)voiceService:(id)service didFailWithError:(NSError *)error;
- (void)voiceService:(id)service audioLevel:(float)level;
@end

@interface OCVoiceService : NSObject

@property (nonatomic, assign) id<OCVoiceServiceDelegate> delegate;
@property (nonatomic, readonly) OCVoiceState state;
@property (nonatomic, assign) NSTimeInterval maxRecordDuration;  /* Default 30s */
@property (nonatomic, assign) float silenceThreshold;            /* Default -40 dB */
@property (nonatomic, assign) NSTimeInterval silenceDuration;    /* Default 2s */

- (BOOL)isAvailable;
- (void)startListening;
- (void)stopListening;

/* Get the recorded audio data (PCM 16-bit, 16kHz mono) */
- (NSData *)recordedAudioData;

@end
