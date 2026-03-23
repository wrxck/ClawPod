/*
 * OCRootViewController.h
 * ClawPod - Root View Controller
 *
 * Simple UINavigationController-based layout.
 * Chat is the primary view. Sessions accessible via nav button.
 * Settings live in Settings.app via PreferenceLoader.
 */

#import <UIKit/UIKit.h>
#import "OCGatewayClient.h"
#import "OCChatSession.h"

@interface OCRootViewController : UIViewController

- (void)updateConnectionState:(OCGatewayConnectionState)state;
- (void)showError:(NSString *)message;
- (void)reloadSessions;
- (void)didReceiveMessage:(OCMessage *)message inSession:(OCChatSession *)session;
- (void)didUpdateStreamingMessage:(OCMessage *)message inSession:(OCChatSession *)session;

@end
