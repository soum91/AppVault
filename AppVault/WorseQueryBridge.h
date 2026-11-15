#import "worse_query.h"
#import "pathleak.h"
#import <Foundation/Foundation.h>
NSArray<NSString *> *AVGroups(void);
NSArray<NSDictionary *> *AVInstalledApps(void);

NSArray<NSDictionary *> *AVDiscoverApps(void (^progress)(NSString *));
void AVDiscoveryCancel(void);
NSString *AVDiscoveryStatus(void);
NSString *AVDiscoveryLog(void);
