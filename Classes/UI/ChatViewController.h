/*
 * OCChatViewController.h
 * LegacyPodClaw - Chat View Controller
 *
 * Full chat interface with:
 * - Streaming message display (real-time delta rendering)
 * - Message bubbles (user/assistant)
 * - Input bar with send button
 * - Connection status banner
 * - Pull-to-load-more history
 * - Keyboard handling
 */

#import <UIKit/UIKit.h>
#import "ChatSession.h"

@interface OCChatViewController : UIViewController <UITableViewDataSource,
                                                     UITableViewDelegate,
                                                     UITextViewDelegate>

- (void)updateStatusText:(NSString *)text color:(UIColor *)color;
- (void)didReceiveMessage:(OCMessage *)message;
- (void)didUpdateStreamingMessage:(OCMessage *)message;

@end
