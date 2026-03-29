/*
 * OCSettingsViewController.h
 * LegacyPodClaw - In-App Settings
 *
 * Reads/writes the same plist as PreferenceLoader so settings
 * stay in sync whether configured here or in Settings.app.
 */

#import <UIKit/UIKit.h>

@interface OCSettingsViewController : UITableViewController <UIAlertViewDelegate>
@end
