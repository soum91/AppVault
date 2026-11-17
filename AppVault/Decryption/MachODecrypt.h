#ifndef AV_MACHO_DECRYPT_H
#define AV_MACHO_DECRYPT_H
#include <stddef.h>
// Returns encrypted slice count, zero for plaintext/non-Mach-O, -1 on malformed input.
int AVInspectMachO(const char *path, char *error, size_t capacity);
// Destination must already be an independent copy. Never modifies the installed source.
int AVDecryptMachO(const char *source, const char *destination, char *error, size_t capacity);
#endif
