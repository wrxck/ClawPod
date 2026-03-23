/*
 * OpenClawPrefsRootListController.h
 * ClawPod - Settings.app PreferenceBundle
 */

#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface OpenClawPrefsRootListController : PSListController
- (void)connectToGateway;
- (void)disconnectFromGateway;
- (void)resetAllSettings;
- (void)testConnection;
@end

@interface OpenClawPrefsAgentController : PSListController
@end

@interface OpenClawPrefsDiagnosticsController : PSListController
@end

@interface OpenClawPrefsDevController : PSListController
- (void)testBanner;
- (void)testMessage;
- (void)testVibrate;
- (void)testLockLabel;
- (void)testOverlay;
- (void)testBrightness;
- (void)testBadge;
- (void)testClearBadge;
- (void)testRespring;
- (void)testClearSMS;
@end
