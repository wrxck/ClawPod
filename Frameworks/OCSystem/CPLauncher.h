/*
 * CPLauncher.h
 * ClawPod - Agentic Home Screen Launcher
 *
 * Replaces the SpringBoard icon grid with an AI-driven launcher.
 * Instead of an icon grid, users see:
 * - A conversation-driven interface (type what you want to do)
 * - AI-suggested apps based on context/time/habits
 * - Quick actions strip
 * - Status dashboard
 * - Recent conversations
 *
 * Toggleable via Settings — can switch back to stock SpringBoard.
 */

#import <UIKit/UIKit.h>

@interface CPLauncher : UIView <UITextFieldDelegate, UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, readonly) BOOL isActive;

/* Create the launcher view for the given frame (screen bounds) */
- (instancetype)initWithFrame:(CGRect)frame;

/* Activate/deactivate (swap with stock SpringBoard) */
- (void)activate;
- (void)deactivate;

/* Refresh data (suggested apps, status, etc.) */
- (void)refresh;

/* Launch an app by bundle ID (used by AI) */
- (void)launchApp:(NSString *)bundleId;

/* Show search results for a query */
- (void)showResultsForQuery:(NSString *)query;

@end

/* Check if launcher is enabled in prefs */
BOOL CPLauncherIsEnabled(void);
