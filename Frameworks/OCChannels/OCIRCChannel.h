/*
 * OCIRCChannel.h
 * ClawPod - IRC Channel (RFC 2812)
 */
#import <Foundation/Foundation.h>
#import "OCChannelManager.h"

@interface OCIRCChannel : NSObject <OCChannel, NSStreamDelegate>
@property (nonatomic, copy) NSString *server;
@property (nonatomic, assign) uint16_t port;       // Default 6667
@property (nonatomic, copy) NSString *nickname;
@property (nonatomic, copy) NSString *password;     // NickServ or server password
@property (nonatomic, retain) NSArray *channels;    // #channel1, #channel2
@property (nonatomic, assign) BOOL useTLS;
@property (nonatomic, assign) id<OCChannelManagerDelegate> messageDelegate;
- (instancetype)initWithServer:(NSString *)server nickname:(NSString *)nick;
@end
