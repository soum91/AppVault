#ifndef AppVault_WorseQueryBridge_h
#define AppVault_WorseQueryBridge_h
#include <stdbool.h>
#include <stdint.h>
int64_t appvault_worse_query(const char *target, const char *group, bool alt_flags, bool create_dir);
void appvault_worse_query_release(void);
#endif
