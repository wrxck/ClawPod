/*
 * OCConnectionService.m
 * ClawPod - Gateway Discovery Implementation
 *
 * Uses NSNetServiceBrowser for Bonjour/mDNS discovery of
 * _openclaw-gw._tcp services on the local network.
 */

#import "ConnectionService.h"

static NSString *const kServiceType = @"_openclaw-gw._tcp.";
static NSString *const kServiceDomain = @"local.";

@implementation OCDiscoveredGateway

- (void)dealloc {
    [_name release]; [_host release]; [_version release]; [_stableId release];
    [super dealloc];
}

@end

@interface OCConnectionService () {
    NSNetServiceBrowser *_browser;
    NSMutableArray *_gateways;
    NSMutableArray *_resolvingServices;
}
@end

@implementation OCConnectionService

@synthesize discoveredGateways = _gateways;

- (instancetype)init {
    if ((self = [super init])) {
        _gateways = [[NSMutableArray alloc] initWithCapacity:4];
        _resolvingServices = [[NSMutableArray alloc] initWithCapacity:4];
    }
    return self;
}

- (void)dealloc {
    [self stopDiscovery];
    [_gateways release]; [_resolvingServices release]; [_browser release];
    [super dealloc];
}

- (void)startDiscovery {
    if (_isSearching) return;
    _isSearching = YES;

    [_gateways removeAllObjects];
    [_browser release];
    _browser = [[NSNetServiceBrowser alloc] init];
    _browser.delegate = self;
    [_browser searchForServicesOfType:kServiceType inDomain:kServiceDomain];
}

- (void)stopDiscovery {
    [_browser stop];
    _isSearching = NO;

    for (NSNetService *service in _resolvingServices) {
        [service stop];
    }
    [_resolvingServices removeAllObjects];
}

#pragma mark - NSNetServiceBrowserDelegate

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
           didFindService:(NSNetService *)service
               moreComing:(BOOL)moreComing {
    /* Resolve the service to get host/port */
    service.delegate = self;
    [_resolvingServices addObject:service];
    [service resolveWithTimeout:10.0];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
         didRemoveService:(NSNetService *)service
               moreComing:(BOOL)moreComing {
    /* Find and remove the gateway */
    for (NSUInteger i = 0; i < [_gateways count]; i++) {
        OCDiscoveredGateway *gw = [_gateways objectAtIndex:i];
        if ([gw.name isEqualToString:[service name]]) {
            [_gateways removeObjectAtIndex:i];
            dispatch_async(dispatch_get_main_queue(), ^{
                [_delegate connectionService:self didRemoveGateway:gw];
            });
            break;
        }
    }
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
             didNotSearch:(NSDictionary *)errorDict {
    NSError *error = [NSError errorWithDomain:@"OCConnectionService"
                                         code:-1
                                     userInfo:errorDict];
    dispatch_async(dispatch_get_main_queue(), ^{
        [_delegate connectionService:self didFailDiscoveryWithError:error];
    });
}

#pragma mark - NSNetServiceDelegate

- (void)netServiceDidResolveAddress:(NSNetService *)service {
    [_resolvingServices removeObject:service];

    OCDiscoveredGateway *gw = [[OCDiscoveredGateway alloc] init];
    gw.name = [service name];
    gw.host = [service hostName];
    gw.port = [service port];

    /* Parse TXT record for metadata */
    NSDictionary *txt = [NSNetService dictionaryFromTXTRecordData:[service TXTRecordData]];
    if (txt) {
        NSData *versionData = [txt objectForKey:@"version"];
        if (versionData) {
            gw.version = [[[NSString alloc] initWithData:versionData
                                                encoding:NSUTF8StringEncoding] autorelease];
        }
        NSData *tlsData = [txt objectForKey:@"tls"];
        if (tlsData) {
            gw.supportsTLS = [[[[NSString alloc] initWithData:tlsData
                                                     encoding:NSUTF8StringEncoding] autorelease]
                              isEqualToString:@"1"];
        }
        NSData *idData = [txt objectForKey:@"id"];
        if (idData) {
            gw.stableId = [[[NSString alloc] initWithData:idData
                                                 encoding:NSUTF8StringEncoding] autorelease];
        }
    }

    [_gateways addObject:gw];
    dispatch_async(dispatch_get_main_queue(), ^{
        [_delegate connectionService:self didDiscoverGateway:gw];
    });
    [gw release];
}

- (void)netService:(NSNetService *)service didNotResolve:(NSDictionary *)errorDict {
    [_resolvingServices removeObject:service];
}

#pragma mark - Setup Code Parsing

+ (NSDictionary *)parseSetupCode:(NSString *)code {
    if (!code || [code length] == 0) return nil;

    NSData *jsonData = nil;

    /* Try JSON first */
    jsonData = [code dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
    if (dict) return dict;

    /* Try base64 decode */
    /* iOS 6 doesn't have built-in base64 on NSData, so we'll use a manual approach */
    NSData *decoded = [self _base64Decode:code];
    if (decoded) {
        dict = [NSJSONSerialization JSONObjectWithData:decoded options:0 error:nil];
        if (dict) return dict;
    }

    return nil;
}

+ (NSData *)_base64Decode:(NSString *)base64 {
    /* Minimal base64 decoder for iOS 6 compatibility */
    static const char decodingTable[128] = {
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,62,-1,-1,-1,63,
        52,53,54,55,56,57,58,59,60,61,-1,-1,-1, 0,-1,-1,
        -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9,10,11,12,13,14,
        15,16,17,18,19,20,21,22,23,24,25,-1,-1,-1,-1,-1,
        -1,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,
        41,42,43,44,45,46,47,48,49,50,51,-1,-1,-1,-1,-1
    };

    const char *input = [base64 UTF8String];
    NSUInteger inputLen = strlen(input);
    if (inputLen % 4 != 0) return nil;

    NSUInteger outputLen = (inputLen / 4) * 3;
    if (inputLen > 0 && input[inputLen - 1] == '=') outputLen--;
    if (inputLen > 1 && input[inputLen - 2] == '=') outputLen--;

    NSMutableData *output = [NSMutableData dataWithLength:outputLen];
    uint8_t *outBytes = [output mutableBytes];
    NSUInteger outIdx = 0;

    for (NSUInteger i = 0; i < inputLen; i += 4) {
        uint8_t a = decodingTable[(int)input[i]];
        uint8_t b = decodingTable[(int)input[i+1]];
        uint8_t c = (i+2 < inputLen && input[i+2] != '=') ? decodingTable[(int)input[i+2]] : 0;
        uint8_t d = (i+3 < inputLen && input[i+3] != '=') ? decodingTable[(int)input[i+3]] : 0;

        if (outIdx < outputLen) outBytes[outIdx++] = (a << 2) | (b >> 4);
        if (outIdx < outputLen) outBytes[outIdx++] = (b << 4) | (c >> 2);
        if (outIdx < outputLen) outBytes[outIdx++] = (c << 6) | d;
    }

    return output;
}

@end
