#import "worse_query.h"
#import "pathleak.h"
#import <Foundation/Foundation.h>
NSArray<NSString *> *AVGroups(void);
NSArray<NSDictionary *> *AVInstalledApps(void);

NSArray<NSDictionary *> * _Nonnull AVDiscoverApps(void (^ _Nonnull progress)(NSString * _Nonnull));
void AVDiscoveryCancel(void);
NSString * _Nonnull AVDiscoveryStatus(void);
NSString * _Nonnull AVDiscoveryLog(void);

#import "IPAToolBridge.h"
