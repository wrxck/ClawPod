/*
 * AppDelegate.h
 * LegacyPodClaw - Main Application Delegate
 */

#import <UIKit/UIKit.h>
#import "GatewayClient.h"
#import "ChatSession.h"
#import "Store.h"
#import "MemoryPool.h"
#import "Agent.h"
#import "GatewayServer.h"

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
