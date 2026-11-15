// AppVault integration by soum91. GPL-3.0-or-later.
// Database parser and recent-inode search approach: kolbicz/WQFiles.
// Sandbox primitive: forcequitOS/worse_query.
#import "../WorseQueryBridge.h"
#import "WQAccess.h"
#import "WQLaunchServices.h"
#include <sys/fsgetpath.h>
#include <sys/mount.h>
#include <fcntl.h>
static int cancelled;
static NSString *lastStatus = @"No discovery run yet.";
static NSMutableDictionary<NSString *, NSNumber *> *handles;
static NSString *group;
static NSMutableString *logText;
void AVDiscoveryCancel(void) { __atomic_store_n(&cancelled, 1, __ATOMIC_RELAXED); }
NSString *AVDiscoveryStatus(void) { @synchronized(NSNull.null) { return [lastStatus copy]; } }
void wq_log(NSString *format, ...) {
    va_list args; va_start(args,format);
    NSString *text=[[NSString alloc] initWithFormat:format arguments:args]; va_end(args);
    @synchronized(NSNull.null) {
        if(!logText) logText=[NSMutableString new];
        if(logText.length < 64000) [logText appendFormat:@"%@\n",text];
    }
}
NSString *AVDiscoveryLog(void) { @synchronized(NSNull.null) { return [logText copy] ?: @""; } }
static BOOL grant(NSString *path) {
    NSString *root = @"/private/var/mobile/Containers/Data/InternalDaemon/";
    NSString *canonical = [path hasPrefix:@"/var/"] ? [@"/private" stringByAppendingString:path] : path;
    if(![canonical hasPrefix:root]) return NO;
    NSString *uuid=[[canonical substringFromIndex:root.length] componentsSeparatedByString:@"/"].firstObject;
    if(![[NSUUID alloc] initWithUUIDString:uuid]) return NO;
    NSString *container=[root stringByAppendingString:uuid];
    if(handles[container]) return YES;
    int64_t h=worse_query(container,group,false,false);
    if(h<0) { wq_log(@"Database-container grant failed: %lld",h); return NO; }
    handles[container]=@(h);
    return YES;
}
BOOL wq_stat(NSString *path, struct stat *st) {
    if(!grant(path)) return NO;
    return lstat(path.fileSystemRepresentation,st)==0;
}
NSData *wq_read(NSString *path, NSUInteger limit, NSString **error) {
    if(!grant(path)) { if(error)*error=@"Database-container sandbox extension refused"; return nil; }
    int fd=open(path.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW);
    if(fd<0) { if(error)*error=@"Database open failed"; return nil; }
    struct stat st;
    if(fstat(fd,&st)!=0 || !S_ISREG(st.st_mode) || st.st_size<0) { close(fd); return nil; }
    NSMutableData *data=[NSMutableData dataWithLength:MIN(limit,(NSUInteger)st.st_size)];
    size_t done=0;
    while(done<data.length) {
        ssize_t n=read(fd,(char*)data.mutableBytes+done,data.length-done);
        if(n<=0) { close(fd); return nil; } done+=(size_t)n;
    }
    close(fd); return data;
}
NSArray<NSString *> *wq_list(NSString *path, NSString **error) {
    if(!grant(path)) return nil;
    NSError *e=nil;
    NSArray *a=[NSFileManager.defaultManager contentsOfDirectoryAtPath:path error:&e];
    if(error && e)*error=e.localizedDescription;
    return a;
}
static NSArray *rowsFromStore(NSString *hint) {
    NSArray *paths=wq_ls_container_paths(hint);
    NSMutableArray *rows=[NSMutableArray new];
    for(NSString *path in paths) {
        NSString *normal=[path stringByReplacingOccurrencesOfString:@"/private/var/" withString:@"/var/"];
        if(![normal.stringByDeletingLastPathComponent isEqualToString:@"/var/mobile/Containers/Data/Application"]) continue;
        struct stat st; if(lstat(path.fileSystemRepresentation,&st)!=0 && errno==ENOENT) continue;
        NSString *bid=wq_bundle_id_for_container(path);
        if(!bid.length) continue;
        [rows addObject:@{@"bundleIdentifier":bid,@"localizedName":wq_display_name(bid) ?: bid,@"dataContainerURL":path}];
    }
    return rows;
}
NSArray<NSDictionary *> *AVDiscoverApps(void (^progress)(NSString *)) {
    __atomic_store_n(&cancelled,0,__ATOMIC_RELAXED);
    handles=[NSMutableDictionary new]; logText=[NSMutableString new];
    @try {
        group=nil;
        for(NSString *candidate in AVGroups()) {
            if([NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:candidate]) { group=candidate; break; }
        }
        if(!group) { lastStatus=@"Signing supplied no usable App Group. Scanning cannot grant access; re-sign with an App Group-enabled provisioning profile."; return @[]; }
        wq_log(@"Usable App Group: %@",group);
        NSArray *cached=rowsFromStore(nil);
        if(cached.count) { lastStatus=[NSString stringWithFormat:@"%lu containers from remembered LaunchServices database",(unsigned long)cached.count]; return cached; }
        NSString *probe=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        int fd=open(probe.fileSystemRepresentation,O_CREAT|O_EXCL|O_RDWR,0600);
        struct stat st={0}; struct statfs sfs={0};
        BOOL ok=fd>=0 && fstat(fd,&st)==0 && fstatfs(fd,&sfs)==0;
        char buf[4096];
        BOOL resolves=ok && fsgetpath(buf,sizeof(buf),&sfs.f_fsid,st.st_ino)>0;
        if(fd>=0) close(fd);
        unlink(probe.fileSystemRepresentation);
        if(!resolves) { lastStatus=@"The fsgetpath self-check failed on this device. No scan was started."; return @[]; }
        uint64_t top=st.st_ino;
        NSNumber *saved=[NSUserDefaults.standardUserDefaults objectForKey:@"AVDatabaseScanCursor"];
        uint64_t cursor=saved ? MIN(saved.unsignedLongLongValue,top) : top;
        __block uint64_t next=cursor, done=0;
        __block NSString *found=nil;
        NSLock *lock=[NSLock new];
        CFAbsoluteTime began=CFAbsoluteTimeGetCurrent();
        dispatch_apply(4,dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^(size_t worker) {
            char path[4096]; fsid_t fsid=sfs.f_fsid;
            while(!__atomic_load_n(&cancelled,__ATOMIC_RELAXED) && CFAbsoluteTimeGetCurrent()-began<20) {
                [lock lock];
                if(found || next==0) { [lock unlock]; return; }
                uint64_t last=next, first=last>4096 ? last-4095 : 1;
                next=first-1; [lock unlock];
                for(uint64_t ino=last;ino>=first;ino--) {
                    if((ino&127)==0 && (__atomic_load_n(&cancelled,__ATOMIC_RELAXED) || CFAbsoluteTimeGetCurrent()-began>=20)) return;
                    if(fsgetpath(path,sizeof(path),&fsid,ino)>0) {
                        const char *name=strrchr(path,'/'); name=name ? name+1 : path;
                        if(strncmp(name,"com.apple.LaunchServices-",25)==0 && strstr(name,".csstore")) {
                            NSString *candidate=[NSString stringWithUTF8String:path];
                            if([candidate containsString:@"/Containers/Data/InternalDaemon/"]) {
                                [lock lock]; if(!found) found=candidate; [lock unlock]; return;
                            }
                        }
                    }
                    if(ino==1) break;
                }
                [lock lock]; done+=last-first+1;
                if(progress) progress([NSString stringWithFormat:@"Database search: %llu file IDs checked · %.0fs / 20s",done,CFAbsoluteTimeGetCurrent()-began]);
                [lock unlock];
            }
        });
        if(found) {
            wq_log(@"Database located after %llu IDs in %.1fs",done,CFAbsoluteTimeGetCurrent()-began);
            NSArray *rows=rowsFromStore(found);
            if(rows.count) { [NSUserDefaults.standardUserDefaults removeObjectForKey:@"AVDatabaseScanCursor"]; lastStatus=[NSString stringWithFormat:@"%lu app containers read from LaunchServices",(unsigned long)rows.count]; return rows; }
            lastStatus=@"Located the LaunchServices database, but could not read or decode its container records. See Diagnostics for sandbox and parser results.";
        } else {
            [NSUserDefaults.standardUserDefaults setObject:@(MIN(cursor,next+16384)) forKey:@"AVDatabaseScanCursor"];
            lastStatus=__atomic_load_n(&cancelled,__ATOMIC_RELAXED) ? @"Discovery cancelled. Refresh resumes from the saved search position." : @"No LaunchServices database found in this 20-second search. Refresh continues from the saved position; the app does not start an unlimited full-volume scan.";
        }
        return @[];
    } @finally {
        wq_log(@"%@",lastStatus);
        for(NSNumber *handle in handles.allValues) worse_query_release(handle.longLongValue);
        handles=nil;
    }
}
