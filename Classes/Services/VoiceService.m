/*
 * OCVoiceService.m
 * LegacyPodClaw - Voice Input Implementation
 *
 * Uses AudioQueue API (compatible with iOS 6) for recording.
 * Records PCM 16-bit 16kHz mono for speech recognition.
 * Memory-efficient: uses a circular buffer, max 30s recording.
 */

#import "VoiceService.h"
#import <AVFoundation/AVFoundation.h>

static const int kNumBuffers = 3;
static const int kSampleRate = 16000;
static const int kBitsPerChannel = 16;
static const int kChannels = 1;
static const int kBufferDurationMs = 100;  /* 100ms per buffer */
static const int kBufferSize = (kSampleRate * kBitsPerChannel / 8 * kChannels * kBufferDurationMs) / 1000;
static const int kMaxRecordBytes = kSampleRate * 2 * 30;  /* 30s max at 16kHz 16-bit */

/* AudioQueue callback */
static void AudioInputCallback(void *inUserData,
                                AudioQueueRef inAQ,
                                AudioQueueBufferRef inBuffer,
                                const AudioTimeStamp *inStartTime,
                                UInt32 inNumberPacketDescriptions,
                                const AudioStreamPacketDescription *inPacketDescs);

@interface OCVoiceService () {
    AudioQueueRef _audioQueue;
    AudioQueueBufferRef _audioBuffers[3]; /* kNumBuffers */
    AudioStreamBasicDescription _audioFormat;

    NSMutableData *_recordBuffer;
    NSTimeInterval _recordStartTime;
    NSTimeInterval _lastSoundTime;
    BOOL _isSetup;
}
@end

@implementation OCVoiceService

- (instancetype)init {
    if ((self = [super init])) {
        _state = OCVoiceStateIdle;
        _maxRecordDuration = 30.0;
        _silenceThreshold = -40.0f;
        _silenceDuration = 2.0;
        _recordBuffer = [[NSMutableData alloc] initWithCapacity:kBufferSize * 10];
    }
    return self;
}

- (void)dealloc {
    [self stopListening];
    [_recordBuffer release];
    [super dealloc];
}

- (BOOL)isAvailable {
    /* Check if audio input is available (requires headset mic on iPod Touch 4) */
    AVAudioSession *session = [AVAudioSession sharedInstance];
    return [session inputIsAvailable];
}

- (void)startListening {
    if (_state != OCVoiceStateIdle) return;

    if (![self isAvailable]) {
        NSError *error = [NSError errorWithDomain:@"OCVoiceService" code:-1
            userInfo:@{NSLocalizedDescriptionKey: @"No audio input available. Connect headset with mic."}];
        [_delegate voiceService:self didFailWithError:error];
        return;
    }

    /* Set up audio session */
    NSError *sessionError = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryRecord error:&sessionError];
    [session setActive:YES error:&sessionError];

    if (sessionError) {
        [_delegate voiceService:self didFailWithError:sessionError];
        return;
    }

    [self _setupAudioQueue];

    [_recordBuffer setLength:0];
    _recordStartTime = [[NSDate date] timeIntervalSince1970];
    _lastSoundTime = _recordStartTime;

    OSStatus status = AudioQueueStart(_audioQueue, NULL);
    if (status != noErr) {
        NSError *error = [NSError errorWithDomain:@"OCVoiceService" code:status
            userInfo:@{NSLocalizedDescriptionKey: @"Failed to start audio recording"}];
        [_delegate voiceService:self didFailWithError:error];
        return;
    }

    _state = OCVoiceStateListening;
    [_delegate voiceServiceDidStartListening:self];
}

- (void)stopListening {
    if (_state == OCVoiceStateIdle) return;

    if (_audioQueue) {
        AudioQueueStop(_audioQueue, true);
        for (int i = 0; i < kNumBuffers; i++) {
            if (_audioBuffers[i]) {
                AudioQueueFreeBuffer(_audioQueue, _audioBuffers[i]);
                _audioBuffers[i] = NULL;
            }
        }
        AudioQueueDispose(_audioQueue, true);
        _audioQueue = NULL;
    }

    [[AVAudioSession sharedInstance] setActive:NO error:nil];

    _state = OCVoiceStateIdle;
    [_delegate voiceServiceDidStopListening:self];
}

- (NSData *)recordedAudioData {
    return [[_recordBuffer copy] autorelease];
}

#pragma mark - Audio Queue Setup

- (void)_setupAudioQueue {
    if (_isSetup && _audioQueue) {
        AudioQueueDispose(_audioQueue, true);
    }

    /* Audio format: PCM 16-bit 16kHz mono */
    memset(&_audioFormat, 0, sizeof(_audioFormat));
    _audioFormat.mSampleRate = kSampleRate;
    _audioFormat.mFormatID = kAudioFormatLinearPCM;
    _audioFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    _audioFormat.mBitsPerChannel = kBitsPerChannel;
    _audioFormat.mChannelsPerFrame = kChannels;
    _audioFormat.mBytesPerPacket = kBitsPerChannel / 8 * kChannels;
    _audioFormat.mBytesPerFrame = _audioFormat.mBytesPerPacket;
    _audioFormat.mFramesPerPacket = 1;

    OSStatus status = AudioQueueNewInput(&_audioFormat,
                                          AudioInputCallback,
                                          (__bridge void *)self,
                                          NULL,
                                          kCFRunLoopCommonModes,
                                          0,
                                          &_audioQueue);

    if (status != noErr) return;

    /* Allocate buffers */
    for (int i = 0; i < kNumBuffers; i++) {
        AudioQueueAllocateBuffer(_audioQueue, kBufferSize, &_audioBuffers[i]);
        AudioQueueEnqueueBuffer(_audioQueue, _audioBuffers[i], 0, NULL);
    }

    /* Enable metering for audio levels */
    UInt32 enableMetering = 1;
    AudioQueueSetProperty(_audioQueue, kAudioQueueProperty_EnableLevelMetering,
                           &enableMetering, sizeof(enableMetering));

    _isSetup = YES;
}

#pragma mark - Audio Callback

- (void)_handleAudioBuffer:(AudioQueueBufferRef)buffer {
    if (_state != OCVoiceStateListening) return;

    /* Append audio data (cap at max) */
    NSUInteger newTotal = [_recordBuffer length] + buffer->mAudioDataByteSize;
    if (newTotal <= kMaxRecordBytes) {
        [_recordBuffer appendBytes:buffer->mAudioData length:buffer->mAudioDataByteSize];
    }

    /* Calculate RMS for level metering */
    int16_t *samples = (int16_t *)buffer->mAudioData;
    NSUInteger sampleCount = buffer->mAudioDataByteSize / sizeof(int16_t);
    float rms = 0;
    for (NSUInteger i = 0; i < sampleCount; i++) {
        float sample = samples[i] / 32768.0f;
        rms += sample * sample;
    }
    rms = sqrtf(rms / MAX(sampleCount, 1));
    float dB = 20.0f * log10f(MAX(rms, 0.0001f));

    /* Notify delegate of audio level */
    dispatch_async(dispatch_get_main_queue(), ^{
        [_delegate voiceService:self audioLevel:dB];
    });

    /* Check for silence-based auto-stop */
    if (dB > _silenceThreshold) {
        _lastSoundTime = [[NSDate date] timeIntervalSince1970];
    } else {
        NSTimeInterval silentFor = [[NSDate date] timeIntervalSince1970] - _lastSoundTime;
        if (silentFor > _silenceDuration && [_recordBuffer length] > kBufferSize * 5) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self stopListening];
            });
            return;
        }
    }

    /* Check max duration */
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSince1970] - _recordStartTime;
    if (elapsed >= _maxRecordDuration) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self stopListening];
        });
        return;
    }

    /* Re-enqueue buffer */
    AudioQueueEnqueueBuffer(_audioQueue, buffer, 0, NULL);
}

@end

#pragma mark - C Callback

static void AudioInputCallback(void *inUserData,
                                AudioQueueRef inAQ,
                                AudioQueueBufferRef inBuffer,
                                const AudioTimeStamp *inStartTime,
                                UInt32 inNumberPacketDescriptions,
                                const AudioStreamPacketDescription *inPacketDescs) {
    OCVoiceService *service = (__bridge OCVoiceService *)inUserData;
    [service _handleAudioBuffer:inBuffer];
}
