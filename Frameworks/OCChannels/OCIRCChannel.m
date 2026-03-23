/*
 * OCIRCChannel.m
 * ClawPod - IRC Client Implementation
 *
 * Plain TCP with NSStream. Handles NICK, USER, JOIN, PRIVMSG, PING/PONG.
 */

#import "OCIRCChannel.h"

@interface OCIRCChannel () {
    NSInputStream *_input;
    NSOutputStream *_output;
    NSMutableData *_readBuf;
    BOOL _running, _connected, _registered;
}
@end

@implementation OCIRCChannel
@synthesize channelId = _channelId;
@synthesize isConnected = _connected;

- (instancetype)initWithServer:(NSString *)server nickname:(NSString *)nick {
    if ((self = [super init])) {
        _server = [server copy]; _nickname = [nick copy];
        _port = 6667; _channelId = @"irc";
        _readBuf = [[NSMutableData alloc] initWithCapacity:1024];
    }
    return self;
}
- (void)dealloc {
    [self stop]; [_server release]; [_nickname release]; [_password release];
    [_channels release]; [_readBuf release];
    [super dealloc];
}
- (BOOL)isConfigured { return _server && _nickname; }

- (void)start {
    if (_running) return;
    _running = YES;
    CFReadStreamRef r; CFWriteStreamRef w;
    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)_server, _port, &r, &w);
    _input = (NSInputStream *)r; _output = (NSOutputStream *)w;
    if (_useTLS) {
        NSDictionary *tls = @{(id)kCFStreamSSLLevel: (id)kCFStreamSocketSecurityLevelNegotiatedSSL};
        [_input setProperty:tls forKey:(id)kCFStreamPropertySSLSettings];
        [_output setProperty:tls forKey:(id)kCFStreamPropertySSLSettings];
    }
    [_input setDelegate:self]; [_output setDelegate:self];
    [_input scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    [_output scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    [_input open]; [_output open];
}

- (void)stop {
    _running = NO; _connected = NO; _registered = NO;
    [_input close]; [_output close];
    [_input release]; _input = nil; [_output release]; _output = nil;
}

- (void)stream:(NSStream *)s handleEvent:(NSStreamEvent)ev {
    if (s == _output && ev == NSStreamEventOpenCompleted) {
        if (_password) [self _send:[NSString stringWithFormat:@"PASS %@", _password]];
        [self _send:[NSString stringWithFormat:@"NICK %@", _nickname]];
        [self _send:[NSString stringWithFormat:@"USER %@ 0 * :ClawPod Bot", _nickname]];
    } else if (s == _input && ev == NSStreamEventHasBytesAvailable) {
        uint8_t buf[1024];
        NSInteger n = [_input read:buf maxLength:1024];
        if (n > 0) { [_readBuf appendBytes:buf length:n]; [self _processLines]; }
    } else if (ev == NSStreamEventErrorOccurred || ev == NSStreamEventEndEncountered) {
        _connected = NO;
        if (_running) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5*NSEC_PER_SEC),
            dispatch_get_main_queue(), ^{ [self stop]; [self start]; });
    }
}

- (void)_processLines {
    NSString *all = [[NSString alloc] initWithData:_readBuf encoding:NSUTF8StringEncoding];
    if (!all) { [all release]; return; }
    NSArray *lines = [all componentsSeparatedByString:@"\r\n"];
    [all release];
    /* Keep incomplete last line in buffer */
    NSString *last = [lines lastObject];
    [_readBuf setLength:0];
    if ([last length] > 0) [_readBuf appendData:[last dataUsingEncoding:NSUTF8StringEncoding]];

    for (NSUInteger i = 0; i < [lines count] - 1; i++) {
        [self _handleLine:[lines objectAtIndex:i]];
    }
}

- (void)_handleLine:(NSString *)line {
    if ([line hasPrefix:@"PING"]) {
        [self _send:[line stringByReplacingOccurrencesOfString:@"PING" withString:@"PONG"]];
        return;
    }
    /* :nick!user@host PRIVMSG #channel :message */
    if ([line rangeOfString:@" PRIVMSG "].location != NSNotFound) {
        NSRange bang = [line rangeOfString:@"!"];
        NSString *nick = bang.location != NSNotFound ? [line substringWithRange:NSMakeRange(1, bang.location-1)] : @"?";
        NSArray *parts = [line componentsSeparatedByString:@" PRIVMSG "];
        if ([parts count] < 2) return;
        NSString *rest = [parts objectAtIndex:1];
        NSRange colon = [rest rangeOfString:@" :"];
        if (colon.location == NSNotFound) return;
        NSString *target = [rest substringToIndex:colon.location];
        NSString *text = [rest substringFromIndex:colon.location + 2];

        OCChannelMessage *msg = [[[OCChannelMessage alloc] init] autorelease];
        msg.channelId = @"irc"; msg.chatId = target; msg.senderId = nick;
        msg.senderName = nick; msg.text = text;
        msg.isGroup = [target hasPrefix:@"#"]; msg.isDirect = !msg.isGroup;
        dispatch_async(dispatch_get_main_queue(), ^{
            [_messageDelegate channelManager:nil didReceiveMessage:msg];
        });
    }
    /* RPL_WELCOME (001) - registered */
    if ([line rangeOfString:@" 001 "].location != NSNotFound) {
        _registered = YES; _connected = YES;
        for (NSString *ch in _channels) [self _send:[NSString stringWithFormat:@"JOIN %@", ch]];
    }
}

- (void)_send:(NSString *)line {
    NSString *full = [line stringByAppendingString:@"\r\n"];
    NSData *d = [full dataUsingEncoding:NSUTF8StringEncoding];
    [_output write:[d bytes] maxLength:[d length]];
}

- (void)sendMessage:(NSString *)text toChatId:(NSString *)chatId {
    [self _send:[NSString stringWithFormat:@"PRIVMSG %@ :%@", chatId, text]];
}
- (void)sendMessage:(NSString *)text toChatId:(NSString *)chatId threadId:(NSString *)t {
    [self sendMessage:text toChatId:chatId];
}
- (void)sendReply:(NSString *)text toMessageId:(NSString *)mid chatId:(NSString *)chatId {
    [self sendMessage:text toChatId:chatId];
}
- (NSDictionary *)statusInfo {
    return @{@"server": _server ?: @"", @"registered": @(_registered)};
}
@end
