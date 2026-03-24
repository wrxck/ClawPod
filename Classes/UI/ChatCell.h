/*
 * OCChatCell.h
 * ClawPod - Chat Message Cell
 *
 * Renders user and assistant message bubbles.
 * Efficient: no images, pure CoreGraphics drawing.
 */

#import <UIKit/UIKit.h>
#import "ChatSession.h"

@interface OCChatCell : UITableViewCell

- (void)configureWithMessage:(OCMessage *)message;
+ (CGFloat)heightForMessage:(OCMessage *)message width:(CGFloat)width;

@end
