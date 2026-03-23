/*
 * OCChatViewController.m
 * ClawPod - Chat View Controller
 *
 * iMessage-style chat with:
 * - Blue user bubbles (right), gray assistant bubbles (left)
 * - Immediate message display + auto-scroll
 * - Typing indicator while waiting for response
 * - Keyboard dismiss on tap outside
 * - Error popups when no connection/API key
 */

#import "OCChatViewController.h"
#import "OCChatCell.h"
#import "AppDelegate.h"

static const CGFloat kInputBarHeight = 44.0f;
static const CGFloat kMaxInputHeight = 100.0f;
static const CGFloat kTypingCellHeight = 40.0f;

@interface OCChatViewController () {
    UITableView *_tableView;
    UIView *_inputBar;
    UITextView *_inputTextView;
    UIButton *_sendButton;

    /* Keyboard tracking */
    CGFloat _keyboardHeight;

    /* State */
    BOOL _autoScrollEnabled;
    BOOL _isWaitingForResponse;
    NSTimer *_streamUpdateTimer;
    BOOL _needsStreamUpdate;

    /* Tap to dismiss keyboard */
    UITapGestureRecognizer *_tapDismiss;

    /* Status */
    UILabel *_statusLabel;
}
@end

@implementation OCChatViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor whiteColor];
    _autoScrollEnabled = YES;
    _isWaitingForResponse = NO;

    [self _setupTableView];
    [self _setupInputBar];
    [self _registerKeyboardNotifications];

    /* Tap to dismiss keyboard */
    _tapDismiss = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_dismissKeyboard)];
    _tapDismiss.cancelsTouchesInView = NO;
    [_tableView addGestureRecognizer:_tapDismiss];

    /* Batch stream updates at 10fps */
    _streamUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                          target:self
                                                        selector:@selector(_flushStreamUpdates)
                                                        userInfo:nil
                                                         repeats:YES];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    /* Auto-select first session if none active */
    OCSessionManager *mgr = [AppDelegate shared].sessionManager;
    if (!mgr.activeSession && [mgr.sessions count] > 0) {
        OCChatSession *first = [mgr.sessions objectAtIndex:0];
        [mgr switchToSession:first.sessionKey];
    }

    [_tableView reloadData];
    [self _scrollToBottomAnimated:NO];
}

- (void)dealloc {
    [_streamUpdateTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_tableView release]; [_inputBar release]; [_inputTextView release];
    [_sendButton release]; [_tapDismiss release]; [_statusLabel release];
    [super dealloc];
}

#pragma mark - UI Setup

- (void)_setupTableView {
    CGRect bounds = self.view.bounds;
    CGRect tableFrame = CGRectMake(0, 0,
                                   bounds.size.width,
                                   bounds.size.height - kInputBarHeight);

    _tableView = [[UITableView alloc] initWithFrame:tableFrame style:UITableViewStylePlain];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.backgroundColor = [UIColor whiteColor];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.allowsSelection = NO;

    [self.view addSubview:_tableView];
}

- (void)_setupInputBar {
    CGRect bounds = self.view.bounds;
    CGFloat y = bounds.size.height - kInputBarHeight;

    _inputBar = [[UIView alloc] initWithFrame:CGRectMake(0, y, bounds.size.width, kInputBarHeight)];
    _inputBar.backgroundColor = [UIColor colorWithRed:0.97f green:0.97f blue:0.97f alpha:1.0f];
    _inputBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;

    /* Top border */
    UIView *border = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, bounds.size.width, 0.5f)] autorelease];
    border.backgroundColor = [UIColor colorWithWhite:0.75f alpha:1.0f];
    border.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_inputBar addSubview:border];

    /* Text input */
    CGFloat sendWidth = 56.0f;
    CGFloat textX = 8.0f;
    CGFloat textW = bounds.size.width - sendWidth - textX - 8.0f;

    _inputTextView = [[UITextView alloc] initWithFrame:
        CGRectMake(textX, 7, textW, kInputBarHeight - 14)];
    _inputTextView.delegate = self;
    _inputTextView.font = [UIFont systemFontOfSize:15.0f];
    _inputTextView.backgroundColor = [UIColor whiteColor];
    _inputTextView.layer.cornerRadius = 6.0f;
    _inputTextView.layer.borderColor = [[UIColor colorWithWhite:0.8f alpha:1.0f] CGColor];
    _inputTextView.layer.borderWidth = 0.5f;
    _inputTextView.layer.masksToBounds = YES;
    _inputTextView.returnKeyType = UIReturnKeySend;
    _inputTextView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_inputBar addSubview:_inputTextView];

    /* Send button */
    _sendButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _sendButton.frame = CGRectMake(bounds.size.width - sendWidth - 4, 7, sendWidth, kInputBarHeight - 14);
    [_sendButton setTitle:@"Send" forState:UIControlStateNormal];
    [_sendButton setTitleColor:[UIColor colorWithRed:0.0f green:0.478f blue:1.0f alpha:1.0f]
                      forState:UIControlStateNormal];
    [_sendButton setTitleColor:[UIColor lightGrayColor] forState:UIControlStateDisabled];
    _sendButton.titleLabel.font = [UIFont boldSystemFontOfSize:16.0f];
    _sendButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_sendButton addTarget:self action:@selector(_sendTapped) forControlEvents:UIControlEventTouchUpInside];
    _sendButton.enabled = NO;
    [_inputBar addSubview:_sendButton];

    [self.view addSubview:_inputBar];
}

#pragma mark - Keyboard Dismiss

- (void)_dismissKeyboard {
    [_inputTextView resignFirstResponder];
}

#pragma mark - Actions

- (void)_sendTapped {
    NSString *text = [_inputTextView.text stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([text length] == 0) return;

    /* Check connection / API key before sending */
    AppDelegate *app = [AppDelegate shared];
    OCGatewayConnectionState gwState = app.gateway.connectionState;

    if (gwState != OCGatewayStateConnected) {
        /* Check if local agent has API key */
        if (!app.localAgent.modelConfig.apiKey || [app.localAgent.modelConfig.apiKey length] == 0) {
            UIAlertView *alert = [[UIAlertView alloc]
                initWithTitle:@"Not Connected"
                      message:@"No gateway connection and no API key configured.\n\n"
                               "Go to Settings \u2192 ClawPod to set up a gateway or API key."
                     delegate:nil
            cancelButtonTitle:@"OK"
            otherButtonTitles:nil];
            [alert show];
            [alert release];
            return;
        }
    }

    _inputTextView.text = @"";
    _sendButton.enabled = NO;
    [self _updateInputBarHeight];

    _isWaitingForResponse = YES;
    _autoScrollEnabled = YES;

    OCSessionManager *mgr = app.sessionManager;

    /* Create session if none active */
    if (!mgr.activeSession) {
        [mgr createSession:@"New Chat"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{
            [mgr sendMessage:text];
            [_tableView reloadData];
            [self _scrollToBottomAnimated:YES];
        });
    } else {
        [mgr sendMessage:text];
        /* Message appears immediately via delegate callback */
    }
}

#pragma mark - Public Updates

- (void)updateStatusText:(NSString *)text color:(UIColor *)color {
    /* Status shown in nav title by RootViewController */
}

- (void)didReceiveMessage:(OCMessage *)message {
    _isWaitingForResponse = NO;
    [_tableView reloadData];
    if (_autoScrollEnabled) {
        [self _scrollToBottomAnimated:YES];
    }
}

- (void)didUpdateStreamingMessage:(OCMessage *)message {
    _needsStreamUpdate = YES;
}

- (void)_flushStreamUpdates {
    if (!_needsStreamUpdate) return;
    _needsStreamUpdate = NO;

    NSArray *messages = [self _currentMessages];
    if ([messages count] == 0) return;

    /* Reload last row for streaming content */
    NSUInteger lastIdx = [messages count] - 1;
    /* Add 1 if typing indicator is showing */
    if (_isWaitingForResponse) lastIdx = [messages count] - 1;

    NSIndexPath *ip = [NSIndexPath indexPathForRow:lastIdx inSection:0];
    OCChatCell *cell = (OCChatCell *)[_tableView cellForRowAtIndexPath:ip];
    if (cell) {
        OCMessage *msg = [messages objectAtIndex:lastIdx];
        [cell configureWithMessage:msg];
        /* Recalculate height */
        [_tableView beginUpdates];
        [_tableView endUpdates];
    } else {
        [_tableView reloadData];
    }

    if (_autoScrollEnabled) {
        [self _scrollToBottomAnimated:NO];
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger count = [[self _currentMessages] count];
    /* Add typing indicator row */
    if (_isWaitingForResponse) count++;
    return count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {

    NSArray *messages = [self _currentMessages];

    /* Typing indicator cell */
    if (_isWaitingForResponse && indexPath.row == (NSInteger)[messages count]) {
        static NSString *typingId = @"TypingCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:typingId];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                          reuseIdentifier:typingId] autorelease];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.backgroundColor = [UIColor whiteColor];

            /* Typing bubble */
            UIView *bubble = [[[UIView alloc] initWithFrame:CGRectMake(10, 4, 60, 32)] autorelease];
            bubble.backgroundColor = [UIColor colorWithRed:0.89f green:0.90f blue:0.91f alpha:1.0f];
            bubble.layer.cornerRadius = 16.0f;
            bubble.tag = 100;
            [cell.contentView addSubview:bubble];

            /* Three dots */
            for (int i = 0; i < 3; i++) {
                UIView *dot = [[[UIView alloc] initWithFrame:
                    CGRectMake(14 + i * 14, 12, 8, 8)] autorelease];
                dot.backgroundColor = [UIColor colorWithWhite:0.55f alpha:1.0f];
                dot.layer.cornerRadius = 4.0f;
                dot.tag = 200 + i;
                [bubble addSubview:dot];
            }
        }

        /* Animate dots */
        UIView *bubble = [cell.contentView viewWithTag:100];
        for (int i = 0; i < 3; i++) {
            UIView *dot = [bubble viewWithTag:200 + i];
            [UIView animateWithDuration:0.4
                                  delay:i * 0.15
                                options:UIViewAnimationOptionRepeat | UIViewAnimationOptionAutoreverse
                             animations:^{
                dot.alpha = 0.3f;
            } completion:nil];
        }

        return cell;
    }

    /* Message cell */
    static NSString *cellId = @"ChatCell";
    OCChatCell *cell = (OCChatCell *)[tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[[OCChatCell alloc] initWithStyle:UITableViewCellStyleDefault
                                  reuseIdentifier:cellId] autorelease];
    }

    if (indexPath.row < (NSInteger)[messages count]) {
        OCMessage *msg = [messages objectAtIndex:indexPath.row];
        [cell configureWithMessage:msg];
    }

    return cell;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *messages = [self _currentMessages];

    /* Typing indicator row */
    if (_isWaitingForResponse && indexPath.row == (NSInteger)[messages count]) {
        return kTypingCellHeight;
    }

    if (indexPath.row >= (NSInteger)[messages count]) return 44.0f;

    OCMessage *msg = [messages objectAtIndex:indexPath.row];
    return [OCChatCell heightForMessage:msg width:tableView.bounds.size.width];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    _autoScrollEnabled = NO;
    [self _dismissKeyboard];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    CGFloat offset = scrollView.contentOffset.y;
    CGFloat maxOffset = scrollView.contentSize.height - scrollView.bounds.size.height;
    if (maxOffset - offset < 50) {
        _autoScrollEnabled = YES;
    }
}

#pragma mark - UITextViewDelegate

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range
 replacementText:(NSString *)text {
    if ([text isEqualToString:@"\n"]) {
        [self _sendTapped];
        return NO;
    }
    return YES;
}

- (void)textViewDidChange:(UITextView *)textView {
    _sendButton.enabled = [[textView.text stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]] length] > 0;
    [self _updateInputBarHeight];
}

#pragma mark - Keyboard

- (void)_registerKeyboardNotifications {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(_keyboardWillShow:)
               name:UIKeyboardWillShowNotification object:nil];
    [nc addObserver:self selector:@selector(_keyboardWillHide:)
               name:UIKeyboardWillHideNotification object:nil];
}

- (void)_keyboardWillShow:(NSNotification *)notif {
    NSDictionary *info = [notif userInfo];
    CGRect keyboardFrame = [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    NSTimeInterval duration = [[info objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve = [[info objectForKey:UIKeyboardAnimationCurveUserInfoKey] intValue];

    _keyboardHeight = keyboardFrame.size.height;

    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:duration];
    [UIView setAnimationCurve:curve];

    CGRect bounds = self.view.bounds;
    CGFloat inputH = _inputBar.frame.size.height;
    CGFloat inputY = bounds.size.height - _keyboardHeight - inputH;
    _inputBar.frame = CGRectMake(0, inputY, bounds.size.width, inputH);
    _tableView.frame = CGRectMake(0, 0, bounds.size.width, inputY);

    [UIView commitAnimations];

    if (_autoScrollEnabled) {
        [self _scrollToBottomAnimated:YES];
    }
}

- (void)_keyboardWillHide:(NSNotification *)notif {
    NSDictionary *info = [notif userInfo];
    NSTimeInterval duration = [[info objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve = [[info objectForKey:UIKeyboardAnimationCurveUserInfoKey] intValue];

    _keyboardHeight = 0;

    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:duration];
    [UIView setAnimationCurve:curve];

    CGRect bounds = self.view.bounds;
    CGFloat inputH = _inputBar.frame.size.height;
    CGFloat inputY = bounds.size.height - inputH;
    _inputBar.frame = CGRectMake(0, inputY, bounds.size.width, inputH);
    _tableView.frame = CGRectMake(0, 0, bounds.size.width, inputY);

    [UIView commitAnimations];
}

#pragma mark - Helpers

- (NSArray *)_currentMessages {
    OCChatSession *session = [AppDelegate shared].sessionManager.activeSession;
    return session ? session.messages : @[];
}

- (void)_scrollToBottomAnimated:(BOOL)animated {
    NSInteger count = [_tableView numberOfRowsInSection:0];
    if (count == 0) return;

    NSIndexPath *lastIP = [NSIndexPath indexPathForRow:count - 1 inSection:0];
    [_tableView scrollToRowAtIndexPath:lastIP
                      atScrollPosition:UITableViewScrollPositionBottom
                              animated:animated];
}

- (void)_updateInputBarHeight {
    CGSize textSize = [_inputTextView.text sizeWithFont:_inputTextView.font
                                      constrainedToSize:CGSizeMake(_inputTextView.frame.size.width - 16,
                                                                   kMaxInputHeight)
                                          lineBreakMode:NSLineBreakByWordWrapping];

    CGFloat newHeight = MAX(kInputBarHeight, textSize.height + 20);
    newHeight = MIN(newHeight, kMaxInputHeight);

    if (fabs(newHeight - _inputBar.frame.size.height) < 1.0f) return;

    CGRect bounds = self.view.bounds;
    CGFloat inputY = bounds.size.height - _keyboardHeight - newHeight;

    [UIView animateWithDuration:0.15 animations:^{
        _inputBar.frame = CGRectMake(0, inputY, bounds.size.width, newHeight);
        _inputTextView.frame = CGRectMake(8, 7, _inputTextView.frame.size.width, newHeight - 14);
        _tableView.frame = CGRectMake(0, 0, bounds.size.width, inputY);
    }];
}

@end
