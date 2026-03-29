/*
 * OCSessionListViewController.m
 * LegacyPodClaw - Session List Implementation
 *
 * Lists all chat sessions with swipe-to-delete and new session button.
 */

#import "SessionListViewController.h"
#import "AppDelegate.h"

@implementation OCSessionListViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Sessions";
    self.tableView.backgroundColor = [UIColor colorWithRed:0.12f green:0.13f blue:0.16f alpha:1.0f];
    self.tableView.separatorColor = [UIColor colorWithWhite:0.25f alpha:1.0f];

    /* New session button */
    UIBarButtonItem *addBtn = [[[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                             target:self
                             action:@selector(_newSession)] autorelease];
    self.navigationItem.rightBarButtonItem = addBtn;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)_newSession {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"New Session"
                                                    message:@"Enter a name:"
                                                   delegate:self
                                          cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:@"Create", nil];
    alert.alertViewStyle = UIAlertViewStylePlainTextInput;
    UITextField *tf = [alert textFieldAtIndex:0];
    tf.placeholder = @"Chat name";
    [alert show];
    [alert release];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == 1) {
        NSString *name = [[alertView textFieldAtIndex:0] text];
        if ([name length] == 0) name = @"New Chat";
        [[AppDelegate shared].sessionManager createSession:name];
    }
}

- (void)reloadData {
    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [[AppDelegate shared].sessionManager.sessions count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"SessionCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                       reuseIdentifier:cellId] autorelease];
        cell.backgroundColor = [UIColor colorWithRed:0.15f green:0.16f blue:0.20f alpha:1.0f];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [UIColor lightGrayColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

        /* Selection color */
        UIView *selView = [[[UIView alloc] init] autorelease];
        selView.backgroundColor = [UIColor colorWithRed:0.22f green:0.45f blue:0.85f alpha:0.3f];
        cell.selectedBackgroundView = selView;
    }

    NSArray *sessions = [AppDelegate shared].sessionManager.sessions;
    if (indexPath.row < (NSInteger)[sessions count]) {
        OCChatSession *session = [sessions objectAtIndex:indexPath.row];
        cell.textLabel.text = session.displayName ?: session.sessionKey;

        /* Format last active time */
        NSDateFormatter *fmt = [[[NSDateFormatter alloc] init] autorelease];
        [fmt setDateStyle:NSDateFormatterShortStyle];
        [fmt setTimeStyle:NSDateFormatterShortStyle];
        NSString *detail = [NSString stringWithFormat:@"%lu messages - %@",
                            (unsigned long)session.totalMessages,
                            session.lastActiveAt ? [fmt stringFromDate:session.lastActiveAt] : @""];
        cell.detailTextLabel.text = detail;

        /* Highlight active session */
        OCChatSession *active = [AppDelegate shared].sessionManager.activeSession;
        if (active && [active.sessionKey isEqualToString:session.sessionKey]) {
            cell.textLabel.textColor = [UIColor colorWithRed:0.3f green:0.7f blue:1.0f alpha:1.0f];
        } else {
            cell.textLabel.textColor = [UIColor whiteColor];
        }
    }

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSArray *sessions = [AppDelegate shared].sessionManager.sessions;
    if (indexPath.row < (NSInteger)[sessions count]) {
        OCChatSession *session = [sessions objectAtIndex:indexPath.row];
        [[AppDelegate shared].sessionManager switchToSession:session.sessionKey];

        /* Switch to chat tab */
        if ([self.tabBarController respondsToSelector:@selector(setSelectedIndex:)]) {
            self.tabBarController.selectedIndex = 0;
        }
    }
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSArray *sessions = [AppDelegate shared].sessionManager.sessions;
        if (indexPath.row < (NSInteger)[sessions count]) {
            OCChatSession *session = [sessions objectAtIndex:indexPath.row];
            [[AppDelegate shared].sessionManager deleteSession:session.sessionKey];
        }
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 60.0f;
}

@end
