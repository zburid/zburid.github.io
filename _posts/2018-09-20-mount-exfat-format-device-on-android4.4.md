---
layout: post
title:  "Android 4.4 挂载exFAT格式文件系统"
date:   2018-09-20 14:10:23+0800
categories: notes
description: "Android 4.4 挂载exFAT格式文件系统的记录"
author: zburid
tags:   Android exFAT 文件系统
typora-root-url: ..
show:   true
mermaid: true
---

### 一、基本概念

**`exFAT`**(Extended File Allocation Table)，又名`FAT64`，是一种能特别适合于闪存的文件系统，可支持单个文件超过4GB的大小。
**`FUSE`**(File system in User space)用户空间文件系统，是操作系统中的概念，指完全在用户态实现的文件系统。目前Linux通过内核模块对此进行支持。

### 二、FUSE实现

##### 1、下载 `exFAT` 相关代码并编译

采用基于`FUSE`的方式实现对`exFAT`的支持。`exFAT`源码见[GITHUB](https://github.com/relan/exfat)，为适用于`Android`平台需要修改相关文件。也可以直接采用别人已实现的[源码](https://download.csdn.net/download/look85/10624573)。并将其导入 `external` 目录：

```bash
$ git clone https://github.com/relan/exfat
$ mv exfat /path/to/sdk/external/
```

##### 2、实现exFAT文件系统的自动挂载

在 `/path/to/sdk/system/vold/` 下添加`Exfat.h`和`Exfat.cpp`文件

```cpp
// Exfat.h
#ifndef _EXFAT_H
#define _EXFAT_H

#include <unistd.h>

class Exfat {
public:
    static int check(const char *fsPath);
    static int doMount(const char *fsPath, const char *mountPoint,
                       bool ro, bool remount, bool executable,
                       int ownerUid, int ownerGid, int permMask,
                       bool createLost);
};

#endif
```

```cpp
// Exfat.cpp
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/wait.h>

#include <linux/kdev_t.h>

#define LOG_TAG "Vold"

#include <cutils/log.h>
#include <cutils/properties.h>

#include <logwrap/logwrap.h>
#include "Exfat.h"
#include "VoldUtil.h"

static char EXFAT_FIX_PATH[] = "/system/bin/fsck.exfat";
static char EXFAT_MOUNT_PATH[] = "/system/bin/mount.exfat";

int Exfat::check(const char *fsPath) {

    if (access(EXFAT_FIX_PATH, X_OK)) {
        SLOGW("Skipping fs checks\n");
        return 0;
    }

    int rc = 0;
    int status;
    const char *args[4];
    /* we first use -n to do ntfs detection */
    args[0] = EXFAT_FIX_PATH;
    args[1] = fsPath;
    args[2] = NULL;

    rc = android_fork_execvp(ARRAY_SIZE(args), (char **)args, &status, false,
           true);
    if (rc) {
        errno = ENODATA;
        return -1;
    }
    if (!WIFEXITED(status)) {
        errno = ENODATA;
        return -1;
    }

        status = WEXITSTATUS(status);

        switch(status) {
        case 0:
            SLOGI("ExFat filesystem check completed OK");
            break;

        default:
            SLOGE("Filesystem check failed (unknown exit code %d)", status);
            errno = EIO;
            return -1;
    }

    return 0;
}

int Exfat::doMount(const char *fsPath, const char *mountPoint,
                 bool ro, bool remount, bool executable,
                 int ownerUid, int ownerGid, int permMask, bool createLost) {
    int rc;
    int status;
    char mountData[255];
    const char *args[6];

    /*
     * Note: This is a temporary hack. If the sampling profiler is enabled,
     * we make the SD card world-writable so any process can write snapshots.
     *
     * TODO: Remove this code once we have a drop box in system_server.
     */
    char value[PROPERTY_VALUE_MAX];
    property_get("persist.sampling_profiler", value, "");
    if (value[0] == '1') {
        SLOGW("The SD card is world-writable because the"
            " 'persist.sampling_profiler' system property is set to '1'.");
        permMask = 0;
    }

    sprintf(mountData,
            "utf8,uid=%d,gid=%d,fmask=%o,dmask=%o,"
            "shortname=mixed,nodev,nosuid,dirsync",
            ownerUid, ownerGid, permMask, permMask);

    if (!executable)
        strcat(mountData, ",noexec");
    if (ro)
        strcat(mountData, ",ro");
    if (remount)
        strcat(mountData, ",remount");

    SLOGD("Mounting ntfs with options:%s\n", mountData);

    args[0] = EXFAT_MOUNT_PATH;
    args[1] = "-o";
    args[2] = mountData;
    args[3] = fsPath;
    args[4] = mountPoint;
    args[5] = NULL;

    rc = android_fork_execvp(ARRAY_SIZE(args), (char **)args, &status, false,
           true);
    if (rc && errno == EROFS) {
        SLOGE("%s appears to be a read only filesystem - retrying mount RO", fsPath);
        strcat(mountData, ",ro");
        rc = android_fork_execvp(ARRAY_SIZE(args), (char **)args, &status, false,
           true);
    }
    if (!WIFEXITED(status)) {
        return rc;
    }

    if (rc == 0 && createLost) {
        char *lost_path;
        asprintf(&lost_path, "%s/LOST.DIR", mountPoint);
        if (access(lost_path, F_OK)) {
            /*
             * Create a LOST.DIR in the root so we have somewhere to put
             * lost cluster chains (fsck_msdos doesn't currently do this)
             */
            if (mkdir(lost_path, 0755)) {
                SLOGE("Unable to create LOST.DIR (%s)", strerror(errno));
            }
        }
        free(lost_path);
    }

    return rc;
}
```

在`Android.mk`中添加`Exfat.cpp`

```diff
common_src_files := \
        ...
        Ntfs.cpp \
+       Exfat.cpp \
        ...
```

修改`Volume.cpp`

```cpp
#include "Exfat.h"

int Volume::mountVol_l() {
    for (i = 0; i < n; i++) {
        if (Fat::check(devicePath)) {
          if (Ntfs::check(devicePath)) {
            if (Exfat::check(devicePath)) {
              SLOGW("%s does not contain a FAT or NTFS or ExFAT filesystem\n", devicePath);
            }
          }
        }
        if (Fat::doMount(devicePath, getMountpoint(), false, false, false,
                AID_MEDIA_RW, AID_MEDIA_RW, mask, true)) {
          if (Ntfs::doMount(devicePath, getMountpoint(), false, false, false,
                AID_MEDIA_RW, AID_MEDIA_RW, mask, true)) {
            if (Exfat::doMount(devicePath, getMountpoint(), false, false, false,
                AID_MEDIA_RW, AID_MEDIA_RW, mask, true)) {
                SLOGE("%s failed to mount via VFAT or NTFS or ExFAT (%s)\n", devicePath, strerror(errno));
                continue;
            }
          }
        }
    }
}
```

### 三、NOFUSE实现

由于`FUSE`方法仅能在`Android`系统启动后才能使用，所以在进入`Recovery`模式时并不能挂载`exFAT`。为此我们需要在内核中实现对`exFAT`的支持，采用`exfat-nofuse`：

```bash
$ git clone https://github.com/arter97/exfat-linux/tree/old
$ mv exfat-linux /path/to/sdk/kernel/fs/exfat
```

将`exfat`添加到内核编译系统当中去：

```diff
diff --git a/kernel/fs/Kconfig b/kernel/fs/Kconfig
index 664991afe0..d6070dd2d1 100755
--- a/kernel/fs/Kconfig
+++ b/kernel/fs/Kconfig
@@ -86,9 +86,10 @@ endmenu
 endif # BLOCK

 if BLOCK
-menu "DOS/FAT/NT Filesystems"
+menu "DOS/FAT/ExFAT/NT Filesystems"

 source "fs/fat/Kconfig"
+source "fs/exfat/Kconfig"
 source "fs/ntfs/Kconfig"

 endmenu
diff --git a/kernel/fs/Makefile b/kernel/fs/Makefile
index da0bbb456d..d355b75811 100755
--- a/kernel/fs/Makefile
+++ b/kernel/fs/Makefile
@@ -76,6 +76,7 @@ obj-$(CONFIG_HUGETLBFS)		+= hugetlbfs/
 obj-$(CONFIG_CODA_FS)		+= coda/
 obj-$(CONFIG_MINIX_FS)		+= minix/
 obj-$(CONFIG_FAT_FS)		+= fat/
+obj-$(CONFIG_EXFAT_FS)		+= exfat/
 obj-$(CONFIG_BFS_FS)		+= bfs/
 obj-$(CONFIG_ISO9660_FS)	+= isofs/
```

重新修改`Exfat.cpp`文件，使`Android`系统能够支持`exfat-nofuse`：

```diff
diff --git a/system/vold/Exfat.cpp b/system/vold/Exfat.cpp
index 9f8be6ccd7..371cbc061e 100644
--- a/system/vold/Exfat.cpp
+++ b/system/vold/Exfat.cpp
@@ -14,6 +14,8 @@
 #include <sys/mman.h>
 #include <sys/mount.h>
 #include <sys/wait.h>
+#include <linux/fs.h>
+#include <sys/ioctl.h>

 #include <linux/kdev_t.h>

@@ -26,6 +28,8 @@
 #include "Exfat.h"
 #include "VoldUtil.h"

+#define USE_NOFUSE_EXFAT
+
 static char EXFAT_FIX_PATH[] = "/system/bin/fsck.exfat";
 static char EXFAT_MOUNT_PATH[] = "/system/bin/mount.exfat";

@@ -75,8 +79,44 @@ int Exfat::doMount(const char *fsPath, const char *mountPoint,
                  bool ro, bool remount, bool executable,
                  int ownerUid, int ownerGid, int permMask, bool createLost) {
     int rc;
-    int status;
     char mountData[255];
+
+#if defined(USE_NOFUSE_EXFAT)
+    unsigned long flags;
+
+    flags = MS_NODEV | MS_NOSUID | MS_DIRSYNC;
+
+    flags |= (executable ? 0 : MS_NOEXEC);
+    flags |= (ro ? MS_RDONLY : 0);
+    flags |= (remount ? MS_REMOUNT : 0);
+
+    /*
+     * Note: This is a temporary hack. If the sampling profiler is enabled,
+     * we make the SD card world-writable so any process can write snapshots.
+     *
+     * TODO: Remove this code once we have a drop box in system_server.
+     */
+    char value[PROPERTY_VALUE_MAX];
+    property_get("persist.sampling_profiler", value, "");
+    if (value[0] == '1') {
+        SLOGW("The SD card is world-writable because the"
+            " 'persist.sampling_profiler' system property is set to '1'.");
+        permMask = 0;
+    }
+
+    sprintf(mountData,
+            "iocharset=utf8,uid=%d,gid=%d,fmask=%o,dmask=%o,errors=remount-ro",
+            ownerUid, ownerGid, permMask, permMask);
+
+    rc = mount(fsPath, mountPoint, "exfat", flags, mountData);
+
+    if (rc && errno == EROFS) {
+        SLOGE("%s appears to be a read only filesystem - retrying mount RO", fsPath);
+        flags |= MS_RDONLY;
+        rc = mount(fsPath, mountPoint, "exfat", flags, mountData);
+    }
+#else
+    int status;
     const char *args[6];

     /*
@@ -125,7 +165,7 @@ int Exfat::doMount(const char *fsPath, const char *mountPoint,
     if (!WIFEXITED(status)) {
         return rc;
     }
-
+#endif
     if (rc == 0 && createLost) {
         char *lost_path;
         asprintf(&lost_path, "%s/LOST.DIR", mountPoint);
```

可以注意到`fuse`和`nofuse`两种方式的区别：

```bash
$ /system/bin/mount.exfat -o XXXX /dev/sdb1 /path/to/mount  # fuse 形式
$ mount -t exfat /dev/sdb1 /path/to/mount -o XXXX           # nofuse 形式
```

此时便可以在`Recovery`源码中添加对`exfat`的支持了。

```diff
diff --git bootable/recovery/roots.cpp

+            result = mount(v->blk_device2[1], v->mount_point, "exfat",
+                           MS_NOATIME | MS_NODEV | MS_NODIRATIME, "");
+            if (result && errno == EROFS) {
+              result = mount(v->blk_device2[1], v->mount_point, "exfat",
+                  MS_NOATIME | MS_NODEV | MS_NODIRATIME | MS_RDONLY, "");
+            }
+            if (result == 0) return 0;
```

