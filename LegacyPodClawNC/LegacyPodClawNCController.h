/*
 * LegacyPodClawNCController.h
 * LegacyPodClaw - Notification Center WeeApp Widget
 *
 * Implements BBWeeAppController to add a LegacyPodClaw widget
 * to Notification Center. Shows status, quick input, and
 * last AI response. Tap to open full app.
 */

#import <UIKit/UIKit.h>

@protocol BBWeeAppController <NSObject>
- (UIView *)view;
@optional
- (float)viewHeight;
- (void)viewWillAppear;
- (void)viewDidAppear;
- (void)viewWillDisappear;
- (void)viewDidDisappear;
- (void)loadPlaceholderView;
- (void)loadFullView;
- (void)unloadView;
- (NSURL *)launchURL;
- (NSURL *)launchURLForTapLocation:(CGPoint)location;
@end

@interface LegacyPodClawNCController : NSObject <BBWeeAppController>
@end
