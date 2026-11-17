#include "MachODecrypt.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#ifdef __APPLE__
#include <dlfcn.h>
#include <sys/mman.h>
#include <mach/mach.h>
#endif

typedef struct { uint64_t base, size, command; uint32_t off, length, id, cpu, subtype; } Slice;
typedef struct { Slice slices[64]; unsigned count; } Image;
static int fail(char *e,size_t n,const char *s) { if(n) snprintf(e,n,"%s",s); return -1; }
static uint32_t u32(const uint8_t *p,int be) { return be ? ((uint32_t)p[0]<<24|p[1]<<16|p[2]<<8|p[3]) : ((uint32_t)p[3]<<24|p[2]<<16|p[1]<<8|p[0]); }
static uint64_t u64(const uint8_t *p,int be) { return be ? (uint64_t)u32(p,1)<<32|u32(p+4,1) : (uint64_t)u32(p+4,0)<<32|u32(p,0); }
static int readat(int fd,void *p,size_t n,uint64_t o) { size_t k=0; while(k<n) { ssize_t r=pread(fd,(uint8_t*)p+k,n-k,o+k); if(r<0&&errno==EINTR) continue; if(r<=0)return -1; k+=r; } return 0; }
#ifdef __APPLE__
static int writeat(int fd,const void *p,size_t n,uint64_t o) { size_t k=0; while(k<n) { ssize_t r=pwrite(fd,(const uint8_t*)p+k,n-k,o+k); if(r<0&&errno==EINTR)continue; if(r<=0)return -1; k+=r; } return 0; }
#endif
static int thin(int fd,uint64_t b,uint64_t size,Image *im,char *e,size_t n) {
 uint8_t h[32]; if(size<32||readat(fd,h,32,b))return fail(e,n,"Truncated Mach-O header");
 if(u32(h,0)!=0xfeedfacf)return fail(e,n,"Unsupported Mach-O slice (requires little-endian 64-bit)");
 uint32_t cmds=u32(h+16,0), bytes=u32(h+20,0); if(bytes>size-32||cmds>bytes/8)return fail(e,n,"Invalid Mach-O load-command bounds");
 uint64_t at=32,end=32+(uint64_t)bytes; int found=0;
 for(uint32_t i=0;i<cmds;i++) {
  uint8_t c[24]; if(at>end||end-at<8||readat(fd,c,8,b+at))return fail(e,n,"Truncated load command");
  uint32_t kind=u32(c,0), len=u32(c+4,0); if(len<8||len>end-at)return fail(e,n,"Invalid load command size");
  if(kind==0x21||kind==0x2c) {
   if(found++||len<(kind==0x2c?24:20)||readat(fd,c,20,b+at))return fail(e,n,"Invalid encryption command");
   uint32_t off=u32(c+8,0), length=u32(c+12,0), id=u32(c+16,0);
   if(off>size||length>size-off||(id&&(!length||off<end)))return fail(e,n,"Invalid encrypted range");
   if(id) { if(im->count==64)return fail(e,n,"Too many encrypted slices"); im->slices[im->count++]=(Slice){b,size,b+at+16,off,length,id,u32(h+4,0),u32(h+8,0)}; }
  }
  at+=len;
 }
 if(at!=end)return fail(e,n,"Load-command length mismatch");
 return 0;
}
static int parse(int fd,Image *im,char *e,size_t n) {
 struct stat st; if(fstat(fd,&st)||st.st_size<0)return fail(e,n,"Cannot stat source");
 uint64_t size=st.st_size; if(size<4)return 0; uint8_t h[8]; if(readat(fd,h,4,0))return fail(e,n,"Cannot read source");
 uint32_t magic=u32(h,1); if(u32(h,0)==0xfeedfacf)return thin(fd,0,size,im,e,n);
 if(u32(h,0)==0xfeedface)return fail(e,n,"32-bit Mach-O is unsupported");
 if(magic!=0xcafebabe&&magic!=0xcafebabf&&magic!=0xbebafeca&&magic!=0xbfbafeca)return 0;
 if(size<8||readat(fd,h,8,0))return fail(e,n,"Truncated FAT header");
 int be=(magic==0xcafebabe||magic==0xcafebabf), wide=(magic==0xcafebabf||magic==0xbfbafeca);
 uint32_t count=u32(h+4,be), width=wide?32:20; uint64_t table=8+(uint64_t)count*width;
 if(!count||count>64||table>size)return fail(e,n,"Invalid FAT slice table");
 uint64_t starts[64],ends[64];
 for(uint32_t i=0;i<count;i++) {
  uint8_t a[32]; if(readat(fd,a,width,8+(uint64_t)i*width))return fail(e,n,"Truncated FAT entry");
  uint64_t off=wide?u64(a+8,be):u32(a+8,be), len=wide?u64(a+16,be):u32(a+12,be);
  if(off<table||off>size||len>size-off)return fail(e,n,"FAT slice outside file");
  for(uint32_t j=0;j<i;j++)if(off<ends[j]&&off+len>starts[j])return fail(e,n,"Overlapping FAT slices");
  starts[i]=off; ends[i]=off+len; if(thin(fd,off,len,im,e,n))return -1;
 }
 return 0;
}
int AVInspectMachO(const char *path,char *e,size_t n) {
 int fd=open(path,O_RDONLY); if(fd<0)return fail(e,n,"Cannot open binary"); Image im={0}; int rc=parse(fd,&im,e,n); close(fd); return rc<0?-1:(int)im.count;
}
int AVDecryptMachO(const char *source,const char *destination,char *e,size_t n) {
 int fd=open(source,O_RDONLY); if(fd<0)return fail(e,n,"Cannot read installed binary");
 Image im={0}; if(parse(fd,&im,e,n)) {close(fd);return -1;} if(!im.count){close(fd);return 0;}
#ifndef __APPLE__
 (void)destination;
 close(fd); return fail(e,n,"Decryption requires iOS FairPlay and a licensed device");
#else
 int out=open(destination,O_RDWR); struct stat a,b;
 if(out<0||fstat(fd,&a)||fstat(out,&b)||a.st_size!=b.st_size||(a.st_dev==b.st_dev&&a.st_ino==b.st_ino)) {if(out>=0)close(out);close(fd);return fail(e,n,"Destination must be an independent complete copy");}
 typedef int (*Remap)(void*,size_t,uint32_t,uint32_t,uint32_t);
 Remap remap=(Remap)dlsym(RTLD_DEFAULT,"mremap_encrypted");
 int rc=-1; size_t pg=getpagesize(); uint8_t *plain=malloc(pg),*original=malloc(pg);
 if(!remap||!plain||!original) {fail(e,n,"FairPlay mapping API or memory unavailable");goto done;}
 for(unsigned i=0;i<im.count;i++) {
  Slice s=im.slices[i];
  if(s.cpu!=0x0100000c||s.base%pg||s.off%pg){fail(e,n,"Unsupported encrypted CPU slice or page alignment");goto done;}
  size_t length=((uint64_t)s.off+s.length+pg-1)&~(pg-1);
  void *map=mmap(NULL,length,PROT_READ,MAP_PRIVATE,fd,s.base);
  if(map==MAP_FAILED){snprintf(e,n,"mmap failed: errno %d",errno);goto done;}
  // Model-encryption mapping avoids executing any of the target app's code.
  if(remap((uint8_t*)map+s.off,s.length,2,s.cpu,s.subtype)) {snprintf(e,n,"FairPlay rejected mapping: errno %d (matching App Store license required)",errno);munmap(map,length);goto done;}
  int changed=0,ok=1;
  for(uint64_t k=0;k<s.length;k+=pg) {
   size_t amount=s.length-k<pg?s.length-k:pg; vm_size_t got=0;
   kern_return_t kr=vm_read_overwrite(mach_task_self(),(vm_address_t)((uint8_t*)map+s.off+k),amount,(vm_address_t)plain,&got);
   if(kr!=KERN_SUCCESS||got!=amount){snprintf(e,n,"FairPlay page read failed: Mach %d at offset %llu",kr,(unsigned long long)k);ok=0;break;}
   if(readat(fd,original,amount,s.base+s.off+k)||writeat(out,plain,amount,s.base+s.off+k)){fail(e,n,"Binary read/write failed");ok=0;break;}
   changed|=memcmp(plain,original,amount)!=0;
  }
  munmap(map,length); if(!ok)goto done;
  if(!changed){fail(e,n,"FairPlay returned unchanged bytes; output rejected");goto done;}
  uint32_t zero=0; if(writeat(out,&zero,4,s.command)){fail(e,n,"Cannot update verified encryption command");goto done;}
 }
 if(fsync(out)){fail(e,n,"Cannot flush decrypted output");goto done;} rc=(int)im.count;
 done: free(plain);free(original);close(out);close(fd);return rc;
#endif
}
