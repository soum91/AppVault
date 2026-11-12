//
//  pathleak.m
//  worse_query
//
//  Created by Taj C on 9/2/26.
//

/*
     pathleak - The dumbest arbitrary path enumeration.
     Copyright (C) 2026 Taj C (forcequit)

     This program is free software: you can redistribute it and/or modify
     it under the terms of the GNU General Public License as published by
     the Free Software Foundation, either version 3 of the License, or
     (at your option) any later version.

     This program is distributed in the hope that it will be useful,
     but WITHOUT ANY WARRANTY; without even the implied warranty of
     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
     GNU General Public License for more details.

     You should have received a copy of the GNU General Public License
     along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/

#import <Foundation/Foundation.h>
#include <sys/fsgetpath.h>
#include <sys/mount.h>

// This is just a rewrite of bad_query_list to return an NSString array and run faster
// The way this works is literally just brute-forcing inodes and doing fsgetpath until it gets a matching path, lol.
// Which is still, obviously, dramatically faster than brute-forcing UUIDs.

// It might be possible to derive a sane inode value automagically by just creating a file, doing stat() on it, getting *that* file's inode, then using that for the max_inode count.


static int avCancelled = 0;
void AVPathCancel(void) { __atomic_store_n(&avCancelled, 1, __ATOMIC_RELAXED); }
NSArray<NSString *> *pathleak(NSString *path, uint64_t max_inode) {
    __atomic_store_n(&avCancelled, 0, __ATOMIC_RELAXED);
    struct statfs sfs;
    // The volume can be identified without asking for parent-container access.
    if (statfs("/private/var", &sfs) != 0) return @[];
    fsid_t fsid = sfs.f_fsid;
    NSString *prefix = [[path stringByReplacingOccurrencesOfString:@"/private/var/" withString:@"/var/"] stringByAppendingString:@"/"];
    NSMutableOrderedSet *result = [NSMutableOrderedSet orderedSet];
    char buffer[PATH_MAX];
    for (uint64_t inode = 1; inode <= max_inode; inode++) {
        if (__atomic_load_n(&avCancelled, __ATOMIC_RELAXED)) break;
        ssize_t n = fsgetpath(buffer, sizeof(buffer), &fsid, inode);
        if (n <= 0) continue;
        NSString *candidate = [[NSString stringWithUTF8String:buffer] stringByReplacingOccurrencesOfString:@"/private/var/" withString:@"/var/"];
        if (![candidate hasPrefix:prefix]) continue;
        NSString *relative = [candidate substringFromIndex:prefix.length];
        if (relative.length && ![relative containsString:@"/"]) [result addObject:candidate];
    }
    return result.array;
}
