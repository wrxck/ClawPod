/*
 * OCRootViewController.m
 * ClawPod - Root View Controller
 *
 * Chat-first UI. Nav bar buttons for sessions and connection status.
 * Settings live in Settings.app via PreferenceBundle.
 */

#import "RootViewController.h"
#import "ChatViewController.h"
#import "SessionListViewController.h"
#import "SettingsViewController.h"
#import "AppDelegate.h"

@interface OCRootViewController () {
    OCChatViewController *_chatVC;
}
@end

@implementation OCRootViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"ClawPod";
    self.view.backgroundColor = [UIColor colorWithRed:0.12f green:0.13f blue:0.16f alpha:1.0f];

    /* Nav bar buttons */
    UIBarButtonItem *sessionsBtn = [[[UIBarButtonItem alloc]
        initWithTitle:@"Sessions"
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(_showSessions)] autorelease];
    self.navigationItem.leftBarButtonItem = sessionsBtn;

    UIBarButtonItem *newBtn = [[[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                             target:self
                             action:@selector(_newSession)] autorelease];

    UIButton *gearButton = [UIButton buttonWithType:UIButtonTypeCustom];
    gearButton.frame = CGRectMake(0, 0, 30, 30);
    [gearButton setTitle:@"\u2699\uFE0F" forState:UIControlStateNormal];
    gearButton.titleLabel.font = [UIFont systemFontOfSize:24];
    [gearButton addTarget:self action:@selector(_openSettings) forControlEvents:UIControlEventTouchUpInside];
    UIBarButtonItem *settingsBtn = [[[UIBarButtonItem alloc] initWithCustomView:gearButton] autorelease];

    self.navigationItem.rightBarButtonItems = @[newBtn, settingsBtn];

    /* Embed chat view controller */
    _chatVC = [[OCChatViewController alloc] init];
    [self addChildViewController:_chatVC];
    _chatVC.view.frame = self.view.bounds;
    _chatVC.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_chatVC.view];
    [_chatVC didMoveToParentViewController:self];
}

- (void)_showSessions {
    OCSessionListViewController *sessionsVC = [[[OCSessionListViewController alloc] init] autorelease];
    [self.navigationController pushViewController:sessionsVC animated:YES];
}

- (void)_openSettings {
    OCSettingsViewController *settingsVC = [[[OCSettingsViewController alloc] initWithStyle:UITableViewStyleGrouped] autorelease];
    [self.navigationController pushViewController:settingsVC animated:YES];
}

- (void)_newSession {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"New Session"
                                                    message:@"Enter a name:"
                                                   delegate:self
                                          cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:@"Create", nil];
    alert.alertViewStyle = UIAlertViewStylePlainTextInput;
    [[alert textFieldAtIndex:0] setPlaceholder:@"Chat name"];
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

#pragma mark - Public

- (void)updateConnectionState:(OCGatewayConnectionState)state {
    NSString *statusText;
    switch (state) {
        case OCGatewayStateConnected:     statusText = @"Connected"; break;
        case OCGatewayStateConnecting:    statusText = @"Connecting..."; break;
        case OCGatewayStateAuthenticating: statusText = @"Auth..."; break;
        case OCGatewayStateReconnecting:  statusText = @"Reconnecting..."; break;
        case OCGatewayStateDisconnected:  statusText = @"Offline"; break;
    }
    self.title = [NSString stringWithFormat:@"ClawPod - %@", statusText];
    [_chatVC updateStatusText:statusText color:
     (state == OCGatewayStateConnected)
         ? [UIColor colorWithRed:0.2f green:0.8f blue:0.4f alpha:1.0f]
         : [UIColor orangeColor]];
}

- (void)showError:(NSString *)message {
    UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Error"
                                                     message:message
                                                    delegate:nil
                                           cancelButtonTitle:@"OK"
                                           otherButtonTitles:nil] autorelease];
    [alert show];
}

- (void)reloadSessions {
    /* Update title with session name if active */
    OCChatSession *active = [AppDelegate shared].sessionManager.activeSession;
    if (active.displayName) {
        self.title = active.displayName;
    }
}

- (void)didReceiveMessage:(OCMessage *)message inSession:(OCChatSession *)session {
    [_chatVC didReceiveMessage:message];
}

- (void)didUpdateStreamingMessage:(OCMessage *)message inSession:(OCChatSession *)session {
    [_chatVC didUpdateStreamingMessage:message];
}

- (void)dealloc {
    [_chatVC release];
    [super dealloc];
}

@end
