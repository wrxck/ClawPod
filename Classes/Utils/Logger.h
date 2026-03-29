/*
 * OCLogger.h
 * LegacyPodClaw - Lightweight Logger
 *
 * Rotating file logger with memory-conscious buffering.
 * Writes to Documents/openclaw.log, rotates at 256KB.
 */

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, OCLogLevel) {
    OCLogLevelDebug = 0,
    OCLogLevelInfo,
    OCLogLevelWarn,
    OCLogLevelError
};

@interface OCLogger : NSObject

@property (nonatomic, assign) OCLogLevel minimumLevel;

+ (instancetype)sharedLogger;

- (void)debug:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
- (void)info:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
- (void)warn:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
- (void)error:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);

- (void)flush;

@end

/* Convenience macros */
#define OCLogD(...) [[OCLogger sharedLogger] debug:__VA_ARGS__]
#define OCLogI(...) [[OCLogger sharedLogger] info:__VA_ARGS__]
#define OCLogW(...) [[OCLogger sharedLogger] warn:__VA_ARGS__]
#define OCLogE(...) [[OCLogger sharedLogger] error:__VA_ARGS__]
