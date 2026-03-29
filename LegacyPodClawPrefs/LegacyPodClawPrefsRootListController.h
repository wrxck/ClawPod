/*
 * LegacyPodClawPrefsRootListController.h
 * LegacyPodClaw - Settings.app PreferenceBundle
 */

#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface LegacyPodClawPrefsRootListController : PSListController
- (void)connectToGateway;
- (void)disconnectFromGateway;
- (void)resetAllSettings;
- (void)testConnection;
@end

@interface LegacyPodClawPrefsAgentController : PSListController
@end

@interface LegacyPodClawPrefsDiagnosticsController : PSListController
@end

@interface LegacyPodClawPrefsDevController : PSListController
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
