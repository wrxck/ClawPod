/*
 * AppDelegate.h
 * ClawPod - Main Application Delegate
 */

#import <UIKit/UIKit.h>
#import "OCGatewayClient.h"
#import "OCChatSession.h"
#import "OCStore.h"
#import "OCMemoryPool.h"
#import "OCAgent.h"
#import "OCGatewayServer.h"

@class OCRootViewController;

@interface AppDelegate : UIResponder <UIApplicationDelegate,
                                       OCGatewayClientDelegate,
                                       OCSessionManagerDelegate>

@property (nonatomic, retain) UIWindow *window;
@property (nonatomic, retain) OCRootViewController *rootViewController;

/* Core services */
@property (nonatomic, retain) OCGatewayClient *gateway;
@property (nonatomic, retain) OCStore *store;
@property (nonatomic, retain) OCSessionManager *sessionManager;
@property (nonatomic, retain) OCKeyValueStore *settings;
@property (nonatomic, retain) OCAgent *localAgent;
@property (nonatomic, retain) OCGatewayServer *gatewayServer;

/* Singleton access */
+ (AppDelegate *)shared;

/* Connection */
- (void)connectToGateway;
- (void)disconnectFromGateway;

/* Settings persistence */
- (void)saveConnectionSettings;
- (void)loadConnectionSettings;

@end
