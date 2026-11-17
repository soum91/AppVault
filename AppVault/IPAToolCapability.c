#include "IPAToolBridge.h"
#include <sys/mman.h>
#include <unistd.h>
// Check the exact W^X transition required by the pinned Unicorn patch before
// collecting a password or starting Go's emulator. This does not enable JIT.
bool AVIPACanExecute(void) {
 size_t n=(size_t)getpagesize();
 void *p=mmap(0,n,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANON,-1,0);
 if(p==MAP_FAILED)return false;
 bool allowed=mprotect(p,n,PROT_READ|PROT_EXEC)==0;
 munmap(p,n);return allowed;
}
