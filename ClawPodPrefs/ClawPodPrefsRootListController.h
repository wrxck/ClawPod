/*
 * ClawPodPrefsRootListController.h
 * ClawPod - Settings.app PreferenceBundle
 */

#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface ClawPodPrefsRootListController : PSListController
- (void)connectToGateway;
- (void)disconnectFromGateway;
- (void)resetAllSettings;
- (void)testConnection;
@end

@interface ClawPodPrefsAgentController : PSListController
@end

@interface ClawPodPrefsDiagnosticsController : PSListController
@end

@interface ClawPodPrefsDevController : PSListController
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
