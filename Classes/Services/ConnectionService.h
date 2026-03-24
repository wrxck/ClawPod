/*
 * OCConnectionService.h
 * ClawPod - Gateway Discovery & Connection Service
 *
 * Provides Bonjour/mDNS discovery of ClawPod gateways on the local
 * network, plus manual host entry. Mirrors the discovery mechanism
 * from the original iOS app (_openclaw-gw._tcp service type).
 */

#import <Foundation/Foundation.h>

@interface OCDiscoveredGateway : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *host;
@property (nonatomic, assign) NSUInteger port;
@property (nonatomic, assign) BOOL supportsTLS;
@property (nonatomic, copy) NSString *version;
@property (nonatomic, copy) NSString *stableId;
@end

@protocol OCConnectionServiceDelegate <NSObject>
- (void)connectionService:(id)service didDiscoverGateway:(OCDiscoveredGateway *)gateway;
- (void)connectionService:(id)service didRemoveGateway:(OCDiscoveredGateway *)gateway;
- (void)connectionService:(id)service didFailDiscoveryWithError:(NSError *)error;
@end

@interface OCConnectionService : NSObject <NSNetServiceBrowserDelegate, NSNetServiceDelegate>

@property (nonatomic, assign) id<OCConnectionServiceDelegate> delegate;
@property (nonatomic, readonly) NSArray *discoveredGateways;
@property (nonatomic, readonly) BOOL isSearching;

- (void)startDiscovery;
- (void)stopDiscovery;

/* Parse a setup code (JSON or base64) into connection params */
+ (NSDictionary *)parseSetupCode:(NSString *)code;

@end
