#import "worse_query.h"
#import "pathleak.h"
#import <Foundation/Foundation.h>
NSArray<NSString *> *AVGroups(void);
NSArray<NSDictionary *> *AVInstalledApps(void);

NSArray<NSDictionary *> * _Nonnull AVDiscoverApps(void (^ _Nonnull progress)(NSString * _Nonnull));
void AVDiscoveryCancel(void);
NSString * _Nonnull AVDiscoveryStatus(void);
NSString * _Nonnull AVDiscoveryLog(void);
#import "Decryption/MachODecrypt.h"
BOOL AVHasDecryptionPrivileges(void);
pid_t AVSpawnSigner(NSString * _Nonnull path, NSArray<NSString *> * _Nonnull arguments, int * _Nonnull writeFD, int * _Nonnull readFD);
void AVStopSigner(pid_t pid);
