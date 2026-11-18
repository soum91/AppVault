#import "DecryptorBridge.h"
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>

// Entitlement read only. Never grants a privilege or changes system files.
BOOL AVHasDecryptionPrivileges(void) {
    void *security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW);
    if (!security) return NO;
    CFTypeRef (*taskCreate)(CFAllocatorRef) = dlsym(security, "SecTaskCreateFromSelf");
    CFTypeRef (*copyEntitlement)(CFTypeRef, CFStringRef, CFErrorRef *) =
        dlsym(security, "SecTaskCopyValueForEntitlement");
    if (!taskCreate || !copyEntitlement) { dlclose(security); return NO; }
    CFTypeRef task = taskCreate(NULL);
    if (!task) { dlclose(security); return NO; }
    CFTypeRef value = copyEntitlement(task, CFSTR("com.apple.private.security.no-sandbox"), NULL);
    CFRelease(task);
    BOOL allowed = value && CFGetTypeID(value) == CFBooleanGetTypeID()
        && CFBooleanGetValue(value);
    if (value) CFRelease(value);
    dlclose(security);
    return allowed;
}
