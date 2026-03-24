/*
 * OCSettingsViewController.m
 * ClawPod - In-App Settings
 *
 * Reads/writes /var/mobile/Library/Preferences/ai.openclaw.ios6.plist
 * Posts Darwin notification so app reloads settings live.
 */

#import "SettingsViewController.h"
#import "AppDelegate.h"
#import <notify.h>

#define PREFS_PATH @"/var/mobile/Library/Preferences/ai.openclaw.ios6.plist"

typedef NS_ENUM(NSUInteger, SettingsSection) {
    SettingsSectionGateway = 0,
    SettingsSectionAuth,
    SettingsSectionAgent,
    SettingsSectionServer,
    SettingsSectionActions,
    SettingsSectionAbout,
    SettingsSectionCount
};

@interface OCSettingsViewController () {
    NSMutableDictionary *_prefs;
    NSInteger _editingTag;
}
@end

@implementation OCSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Settings";
    self.tableView.backgroundColor = [UIColor groupTableViewBackgroundColor];

    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                             target:self
                             action:@selector(_done)] autorelease];

    [self _loadPrefs];
}

- (void)_done {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)_loadPrefs {
    [_prefs release];
    _prefs = [[NSMutableDictionary dictionaryWithContentsOfFile:PREFS_PATH] retain];
    if (!_prefs) _prefs = [[NSMutableDictionary alloc] init];
}

- (void)_savePrefs {
    [_prefs writeToFile:PREFS_PATH atomically:YES];
    notify_post("ai.openclaw.ios6/prefsChanged");
    [[AppDelegate shared] loadConnectionSettings];
}

- (NSString *)_prefString:(NSString *)key {
    return [_prefs objectForKey:key] ?: @"";
}

- (BOOL)_prefBool:(NSString *)key {
    return [[_prefs objectForKey:key] boolValue];
}

- (void)dealloc {
    [_prefs release];
    [super dealloc];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return SettingsSectionCount;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case SettingsSectionGateway: return @"Gateway Connection";
        case SettingsSectionAuth:    return @"Authentication";
        case SettingsSectionAgent:   return @"Local Agent";
        case SettingsSectionServer:  return @"Gateway Server";
        case SettingsSectionActions: return @"";
        case SettingsSectionAbout:   return @"About";
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case SettingsSectionGateway:
            return @"Connect to a ClawPod gateway on your network.";
        case SettingsSectionAgent:
            return @"Used when no gateway is connected.";
        case SettingsSectionServer:
            return @"Run the full ClawPod gateway on this iPod. Other devices can connect to it.";
        default: return nil;
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case SettingsSectionGateway: return 4;
        case SettingsSectionAuth:    return 2;
        case SettingsSectionAgent:   return 2;
        case SettingsSectionServer:  return 3;
        case SettingsSectionActions: return 2;
        case SettingsSectionAbout:   return 2;
        default: return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[[UITableViewCell alloc]
        initWithStyle:UITableViewCellStyleValue1
      reuseIdentifier:nil] autorelease];
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;

    switch (indexPath.section) {
        case SettingsSectionGateway: {
            switch (indexPath.row) {
                case 0:
                    cell.textLabel.text = @"Host";
                    cell.detailTextLabel.text = [[self _prefString:@"gatewayHost"] length] > 0
                        ? [self _prefString:@"gatewayHost"] : @"Not set";
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
                case 1:
                    cell.textLabel.text = @"Port";
                    cell.detailTextLabel.text = [[self _prefString:@"gatewayPort"] length] > 0
                        ? [self _prefString:@"gatewayPort"] : @"18789";
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
                case 2: {
                    cell.textLabel.text = @"Use TLS";
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    UISwitch *sw = [[[UISwitch alloc] init] autorelease];
                    sw.on = [self _prefBool:@"useTLS"];
                    sw.tag = 1000;
                    [sw addTarget:self action:@selector(_switchChanged:) forControlEvents:UIControlEventValueChanged];
                    cell.accessoryView = sw;
                    break;
                }
                case 3: {
                    cell.textLabel.text = @"Self-Signed Certs";
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    UISwitch *sw = [[[UISwitch alloc] init] autorelease];
                    sw.on = [self _prefBool:@"allowSelfSigned"];
                    sw.tag = 1001;
                    [sw addTarget:self action:@selector(_switchChanged:) forControlEvents:UIControlEventValueChanged];
                    cell.accessoryView = sw;
                    break;
                }
            }
            break;
        }
        case SettingsSectionAuth: {
            switch (indexPath.row) {
                case 0:
                    cell.textLabel.text = @"Token";
                    cell.detailTextLabel.text = [[self _prefString:@"authToken"] length] > 0 ? @"\u2022\u2022\u2022\u2022\u2022" : @"Not set";
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
                case 1:
                    cell.textLabel.text = @"Password";
                    cell.detailTextLabel.text = [[self _prefString:@"authPassword"] length] > 0 ? @"\u2022\u2022\u2022\u2022\u2022" : @"Not set";
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
            }
            break;
        }
        case SettingsSectionAgent: {
            switch (indexPath.row) {
                case 0:
                    cell.textLabel.text = @"API Key";
                    cell.detailTextLabel.text = [[self _prefString:@"apiKey"] length] > 0 ? @"\u2022\u2022\u2022\u2022\u2022" : @"Not set";
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
                case 1:
                    cell.textLabel.text = @"Model";
                    cell.detailTextLabel.text = [[self _prefString:@"modelId"] length] > 0
                        ? [self _prefString:@"modelId"] : @"claude-sonnet-4-20250514";
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
            }
            break;
        }
        case SettingsSectionServer: {
            switch (indexPath.row) {
                case 0: {
                    cell.textLabel.text = @"Gateway Server";
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    UISwitch *sw = [[[UISwitch alloc] init] autorelease];
                    sw.on = [AppDelegate shared].gatewayServer.isRunning;
                    sw.tag = 2000;
                    [sw addTarget:self action:@selector(_switchChanged:) forControlEvents:UIControlEventValueChanged];
                    cell.accessoryView = sw;
                    break;
                }
                case 1:
                    cell.textLabel.text = @"Server Port";
                    cell.detailTextLabel.text = [[self _prefString:@"serverPort"] length] > 0
                        ? [self _prefString:@"serverPort"] : @"18789";
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
                case 2: {
                    BOOL running = [AppDelegate shared].gatewayServer.isRunning;
                    cell.textLabel.text = @"Status";
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    if (running) {
                        NSUInteger clients = [[AppDelegate shared].gatewayServer.connectedClients count];
                        cell.detailTextLabel.text = [NSString stringWithFormat:@"Running (%lu clients)",
                                                     (unsigned long)clients];
                        cell.detailTextLabel.textColor = [UIColor colorWithRed:0.2f green:0.7f blue:0.3f alpha:1.0f];
                    } else {
                        cell.detailTextLabel.text = @"Stopped";
                        cell.detailTextLabel.textColor = [UIColor grayColor];
                    }
                    break;
                }
            }
            break;
        }
        case SettingsSectionActions: {
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.detailTextLabel.text = nil;
            if (indexPath.row == 0) {
                BOOL connected = [AppDelegate shared].gateway.connectionState == OCGatewayStateConnected;
                cell.textLabel.text = connected ? @"Disconnect" : @"Connect to Gateway";
                cell.textLabel.textColor = connected
                    ? [UIColor colorWithRed:0.9f green:0.2f blue:0.2f alpha:1.0f]
                    : [UIColor colorWithRed:0.0f green:0.478f blue:1.0f alpha:1.0f];
            } else {
                cell.textLabel.text = @"Reset All Settings";
                cell.textLabel.textColor = [UIColor colorWithRed:0.9f green:0.2f blue:0.2f alpha:1.0f];
            }
            break;
        }
        case SettingsSectionAbout: {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.accessoryType = UITableViewCellAccessoryNone;
            if (indexPath.row == 0) {
                cell.textLabel.text = @"Version";
                cell.detailTextLabel.text = @"0.1.0";
            } else {
                cell.textLabel.text = @"Device";
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ iOS %@",
                    [[UIDevice currentDevice] model],
                    [[UIDevice currentDevice] systemVersion]];
            }
            break;
        }
    }

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == SettingsSectionGateway) {
        if (indexPath.row == 0) {
            [self _showInput:@"Gateway Host" key:@"gatewayHost" placeholder:@"192.168.1.x" secure:NO tag:100];
        } else if (indexPath.row == 1) {
            [self _showInput:@"Gateway Port" key:@"gatewayPort" placeholder:@"18789" secure:NO tag:101];
        }
    } else if (indexPath.section == SettingsSectionAuth) {
        if (indexPath.row == 0) {
            [self _showInput:@"Auth Token" key:@"authToken" placeholder:@"Token" secure:YES tag:200];
        } else {
            [self _showInput:@"Password" key:@"authPassword" placeholder:@"Password" secure:YES tag:201];
        }
    } else if (indexPath.section == SettingsSectionAgent) {
        if (indexPath.row == 0) {
            [self _showInput:@"API Key" key:@"apiKey" placeholder:@"sk-ant-..." secure:YES tag:300];
        } else {
            [self _showInput:@"Model ID" key:@"modelId" placeholder:@"claude-sonnet-4-20250514" secure:NO tag:301];
        }
    } else if (indexPath.section == SettingsSectionServer) {
        if (indexPath.row == 1) {
            [self _showInput:@"Server Port" key:@"serverPort" placeholder:@"18789" secure:NO tag:400];
        }
    } else if (indexPath.section == SettingsSectionActions) {
        if (indexPath.row == 0) {
            BOOL connected = [AppDelegate shared].gateway.connectionState == OCGatewayStateConnected;
            if (connected) {
                [[AppDelegate shared] disconnectFromGateway];
            } else {
                [[AppDelegate shared] connectToGateway];
            }
            [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        } else {
            [_prefs removeAllObjects];
            [self _savePrefs];
            [tableView reloadData];
        }
    }
}

#pragma mark - Input Dialog

- (void)_showInput:(NSString *)title key:(NSString *)key placeholder:(NSString *)placeholder
            secure:(BOOL)secure tag:(NSInteger)tag {
    _editingTag = tag;

    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
                                                    message:nil
                                                   delegate:self
                                          cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:@"Save", nil];
    alert.alertViewStyle = secure ? UIAlertViewStyleSecureTextInput : UIAlertViewStylePlainTextInput;
    alert.tag = tag;

    UITextField *tf = [alert textFieldAtIndex:0];
    tf.placeholder = placeholder;
    tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    tf.autocorrectionType = UITextAutocorrectionTypeNo;

    /* Pre-fill current value (except secure fields) */
    if (!secure) {
        tf.text = [self _prefString:key];
    }

    [alert show];
    [alert release];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex != 1) return;

    NSString *value = [[alertView textFieldAtIndex:0] text];
    NSString *key = nil;

    switch (alertView.tag) {
        case 100: key = @"gatewayHost"; break;
        case 101: key = @"gatewayPort"; break;
        case 200: key = @"authToken"; break;
        case 201: key = @"authPassword"; break;
        case 300: key = @"apiKey"; break;
        case 301: key = @"modelId"; break;
        case 400: key = @"serverPort"; break;
    }

    if (key && value) {
        if ([value length] > 0) {
            [_prefs setObject:value forKey:key];
        } else {
            [_prefs removeObjectForKey:key];
        }
        [self _savePrefs];
        [self.tableView reloadData];
    }
}

#pragma mark - Switches

- (void)_switchChanged:(UISwitch *)sw {
    switch (sw.tag) {
        case 1000:
            [_prefs setObject:@(sw.on) forKey:@"useTLS"];
            break;
        case 1001:
            [_prefs setObject:@(sw.on) forKey:@"allowSelfSigned"];
            break;
        case 2000: {
            if (sw.on) {
                /* Start gateway server */
                OCGatewayConfig *cfg = [[[OCGatewayConfig alloc] init] autorelease];
                NSString *portStr = [self _prefString:@"serverPort"];
                cfg.port = [portStr length] > 0 ? [portStr intValue] : 18789;
                cfg.authMode = @"none"; /* Can be configured later */
                cfg.defaultApiKey = [self _prefString:@"apiKey"];
                cfg.defaultModelId = [self _prefString:@"modelId"];

                OCGatewayServer *server = [[OCGatewayServer alloc] initWithConfig:cfg];
                [AppDelegate shared].gatewayServer = server;
                NSError *err = nil;
                if (![server start:&err]) {
                    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Server Error"
                        message:[err localizedDescription] delegate:nil
                        cancelButtonTitle:@"OK" otherButtonTitles:nil];
                    [alert show]; [alert release];
                    sw.on = NO;
                }
                [server release];
            } else {
                [[AppDelegate shared].gatewayServer stop];
                [AppDelegate shared].gatewayServer = nil;
            }
            [self.tableView reloadData];
            break;
        }
    }
    [self _savePrefs];
}

@end
