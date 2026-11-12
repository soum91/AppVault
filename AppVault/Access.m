#import "WorseQueryBridge.h"
#import <dlfcn.h>
#import <objc/message.h>
NSArray<NSString *> *AVGroups(void) {
 void *sec=dlopen("/System/Library/Frameworks/Security.framework/Security",RTLD_NOW);
 CFTypeRef (*create)(CFAllocatorRef)=dlsym(sec,"SecTaskCreateFromSelf");
 CFTypeRef (*value)(CFTypeRef,CFStringRef,CFErrorRef*)=dlsym(sec,"SecTaskCopyValueForEntitlement");
 if(!create || !value) return @[];
 CFTypeRef task=create(NULL);
 if(!task) return @[];
 CFTypeRef groups=value(task,CFSTR("com.apple.security.application-groups"),NULL);
 CFRelease(task);
 if(!groups) return @[];
 id obj=CFBridgingRelease(groups);
 return [obj isKindOfClass:NSArray.class] ? obj : @[];
}
NSArray<NSDictionary *> *AVInstalledApps(void) {
 dlopen("/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices",RTLD_NOW);
 Class cls=NSClassFromString(@"LSApplicationWorkspace");
 SEL ws=NSSelectorFromString(@"defaultWorkspace"), all=NSSelectorFromString(@"allApplications");
 if(![cls respondsToSelector:ws]) return @[];
 id workspace=((id(*)(id,SEL))objc_msgSend)(cls,ws);
 if(![workspace respondsToSelector:all]) return @[];
 NSArray *apps=((id(*)(id,SEL))objc_msgSend)(workspace,all);
 NSMutableArray *rows=[NSMutableArray array];
 for(id app in apps) {
   NSMutableDictionary *row=[NSMutableDictionary dictionary];
   for(NSString *key in @[@"localizedName",@"bundleIdentifier",@"bundleURL",@"dataContainerURL"]) {
     SEL sel=NSSelectorFromString(key);
     if([app respondsToSelector:sel]) {
       id val=((id(*)(id,SEL))objc_msgSend)(app,sel);
       if(val) row[key]=[val isKindOfClass:NSURL.class] ? [val path] : [val description];
     }
   }
   if(row[@"bundleIdentifier"]) [rows addObject:row];
 }
 return rows;
}
