#import <Foundation/Foundation.h>
#include <sys/stat.h>
void wq_log(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
BOOL wq_stat(NSString *path, struct stat *st);
NSData *wq_read(NSString *path, NSUInteger limit, NSString **error);
NSArray<NSString *> *wq_list(NSString *path, NSString **error);
