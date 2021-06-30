---
layout: post
title:  "HUB与读卡器芯片USB2660调试"
date:   2020-09-24 13:19:58 +0800
categories: notes
description: "Android4.4平台下HUB与读卡器芯片USB2660调试记录"
author: zburid
tags:   HUB 读卡器 Android USB2660
typora-root-url: ..
show:   true
---

### 一、芯片USB2660简介

`Microchip`下的`USB2660`是一款支持超快速USB 2.0 HUB芯片，有两个闪存介质控制器，支持多种格式的闪存介质：

    Secure DigitalTM (SD)
    MultiMediaCardTM (MMC)
    Memory Stick® (MS)
    xD-Picture CardTM (xD)

### 二、Vold实现U盘与SD卡挂载

#### 1、`fstab`文件加载

```cpp
/* system/vold/main.cpp */
static int process_config(VolumeManager *vm)
{
    ...
    property_get("ro.hardware", propbuf, "");
    snprintf(fstab_filename, sizeof(fstab_filename), FSTAB_PREFIX"%s", propbuf);

    property_get("ro.bootmode", propbuf, "");
    if (!strcmp(propbuf, "emmc"))
        sprintf(fstab_filename, "%s.%s", fstab_filename, propbuf);

    fstab = fs_mgr_read_fstab(fstab_filename);
    if (!fstab) {
        SLOGE("failed to open %s\n", fstab_filename);
        return -1;
    }

    /* Loop through entries looking for ones that vold manages */
    for (i = 0; i < fstab->num_entries; i++) {
        if (fs_mgr_is_voldmanaged(&fstab->recs[i])) {
            ...
            dv = new DirectVolume(vm, &(fstab->recs[i]), flags);
            ...
            vm->addVolume(dv);
        }
    }
    ...
}
```

如上函数在开机时执行加载`fstab.{ro.hardware}`或`fstab.{ro.hardware}.{ro.bootmode}`文件，需要注意的是要配置为`voldmanaged`才能使能Vold管理该配置：
```shell
# src(uevent[DEVPATH] tag)              mount point         type    mount flags     fs_mgr flags                device2
/dev/block/platform/bdm/by-name/system  /system             ext4    ro              wait
/devices/xxx-sdhc.0                     /storage/sdcard1    vfat    defaults        voldmanaged=sdcard1:auto
/devices/xxx-ehci                       /storage/usb0       vfat    defaults        voldmanaged=usb0:auto       /devices/dwc_otg
```

#### 2、`uevent`事件获取

`uevent`事件由底层`kernel`产生并发出，由`NetlinkManager`读取、`NetlinkListener`监听、`NetlinkEvent`解析、`NetlinkHandler`判断是否为`block`事件并交由`DirectVolume`处理。
`DirectVolume::handleBlockEvent`获取`uevent`中的`DEVPATH`，并将其与之前加载的`fstab`每条参数对比，判断出当前的挂载点并执行`Disk`与`Partition`的挂载与移除。

原始`NetlinkEvent`如下：

```text
add@/devices/virtual/bdi/8:32
add@/devices/dwc_otg/usb1/1-1/1-1.2/1-1.2:1.0/host1/target1:0:0/1:0:0:0/block/sdc
add@/devices/dwc_otg/usb1/1-1/1-1.2/1-1.2:1.0/host1/target1:0:0/1:0:0:0/block/sdc/sdc1
remove@/devices/dwc_otg/usb1/1-1/1-1.2/1-1.2:1.0/host4/target4:0:0/4:0:0:0/scsi_generic/sg2
remove@/devices/dwc_otg/usb1/1-1/1-1.2/1-1.2:1.0/host4/target4:0:0/4:0:0:0/scsi_disk/4:0:0:0
remove@/devices/dwc_otg/usb1/1-1/1-1.2/1-1.2:1.0/host4/target4:0:0/4:0:0:0/block/sdc/sdc1
change@/devices/dwc_otg/usb1/1-1/1-1.1/1-1.1:1.0/host19/target19:0:0/19:0:0:0/block/sdb
```

由于`DEVPATH`通常都是如下格式：

```text
/devices/virtual/block/loop6
/devices/xxx-sdhc.3/mmc_host/mmc0/mmc0:0001/block/mmcblk0/mmcblk0boot1
/devices/dwc_otg/usb1/1-1/1-1.2/1-1.2:1.0/host1/target1:0:0/1:0:0:0/block/sdc
/devices/dwc_otg/usb1/1-1/1-1.1/1-1.1:1.0/host0/target0:0:0/0:0:0:1/block/sdb/sdb1
```
可见当HUB接入USB总线时，SD卡与U盘的`DEVPATH`都是以`/devices/dwc_otg/`开头的格式，在`fstab`列表中无法实现区分，因此修改`fstab`如下：

```shell
/block/sdb      /mnt/media_rw/sdcard1           vfat    defaults        voldmanaged=sdcard1:auto
/block/sdc      /mnt/media_rw/usb0              vfat    defaults        voldmanaged=usb0:auto   /block/sda
```

而采用如上`/block/sdx`形式的话，需要更改`DirectVolume::handleBlockEvent`函数如下：

```diff
@@ -104,7 +134,7 @@ int DirectVolume::handleBlockEvent(NetlinkEvent *evt) {
     PathCollection::iterator  it;
     for (it = mPaths->begin(); it != mPaths->end(); ++it) {
         connectedType++;
-        if (!strncmp(dp, *it, strlen(*it))) { // 判断fstab配置字符串是否与DEVPATH最前相等
+        if (strstr(dp, *it)) {                // 判断fstab配置字符串出现在DEVPATH里面
             /* We can handle this disk */
             int action = evt->getAction();
             const char *devtype = evt->findParam("DEVTYPE");
```

除此之外，`sda`、`sdb`与`sdc`所用的`major`设备号一致，而`minor`设备号是分别从`0`、`16`和`32`开始的，修正程序如下：

```diff
@@ -123,14 +153,14 @@ int DirectVolume::handleBlockEvent(NetlinkEvent *evt) {
                 }
                 if (!strcmp(devtype, "disk")) {
                     const char *tmp = evt->findParam("NPARTS");
-                    if ((mDiskMajor != -1) ||
+                    if (/*(mDiskMajor != -1) ||*/
                            (major == 240 && (tmp==NULL || atoi(tmp)==0))) {
                         break;
                     }
                     setStorageType(connectedType);
                     handleDiskAdded(dp, evt);
                 } else {
-                    if ((mDiskMajor != major) || (mDiskMinor > minor) || (mDiskMinor+15 < minor)) {
+                    if ((mDiskMajor != major) || (mDiskMinor > minor)/* || (mDiskMinor+15 < minor)*/) {
                         break;
                     }
                     handlePartitionAdded(dp, evt);
```

以上，基本上可以实现`/block/sda`与`/block/sdc`挂载到`/mnt/media_rw/usb0`上，`/block/sdb`挂在到`/mnt/media_rw/sdcard1`上。

### 三、SD卡热插拔检测

在实现了SD卡的正常挂载后，发现热拔插SD卡时，内核和应用层均不能检测到SD卡的拔出事件：

```shell
$ cat sys/kernel/debug/usb/devices

T:  Bus=03 Lev=00 Prnt=00 Port=00 Cnt=00 Dev#=  1 Spd=12   MxCh= 1
B:  Alloc=  0/900 us ( 0%), #Int=  0, #Iso=  0
D:  Ver= 1.10 Cls=09(hub  ) Sub=00 Prot=00 MxPS=64 #Cfgs=  1
P:  Vendor=1d6b ProdID=0001 Rev= 3.18
S:  Manufacturer=Linux 3.18.24-xxx ohci_hcd
S:  Product=OHCI Host Controller
S:  SerialNumber=xxx
C:* #Ifs= 1 Cfg#= 1 Atr=e0 MxPwr=  0mA
I:* If#= 0 Alt= 0 #EPs= 1 Cls=09(hub  ) Sub=00 Prot=00 Driver=hub
E:  Ad=81(I) Atr=03(Int.) MxPS=   2 Ivl=255ms

T:  Bus=02 Lev=00 Prnt=00 Port=00 Cnt=00 Dev#=  1 Spd=480  MxCh= 1
B:  Alloc=  0/800 us ( 0%), #Int=  0, #Iso=  0
D:  Ver= 2.00 Cls=09(hub  ) Sub=00 Prot=00 MxPS=64 #Cfgs=  1
P:  Vendor=1d6b ProdID=0002 Rev= 3.18
S:  Manufacturer=Linux 3.18.24-xxx ehci_hcd
S:  Product=EHCI Host Controller
S:  SerialNumber=xxx-ehci
C:* #Ifs= 1 Cfg#= 1 Atr=e0 MxPwr=  0mA
I:* If#= 0 Alt= 0 #EPs= 1 Cls=09(hub  ) Sub=00 Prot=00 Driver=hub
E:  Ad=81(I) Atr=03(Int.) MxPS=   4 Ivl=256ms

T:  Bus=01 Lev=00 Prnt=00 Port=00 Cnt=00 Dev#=  1 Spd=480  MxCh= 1
B:  Alloc=  0/800 us ( 0%), #Int=  0, #Iso=  0
D:  Ver= 2.00 Cls=09(hub  ) Sub=00 Prot=01 MxPS=64 #Cfgs=  1
P:  Vendor=1d6b ProdID=0002 Rev= 3.18
S:  Manufacturer=Linux 3.18.24-xxx dwc_otg_hcd
S:  Product=DWC OTG Controller
S:  SerialNumber=dwc_otg
C:* #Ifs= 1 Cfg#= 1 Atr=e0 MxPwr=  0mA
I:* If#= 0 Alt= 0 #EPs= 1 Cls=09(hub  ) Sub=00 Prot=00 Driver=hub
E:  Ad=81(I) Atr=03(Int.) MxPS=   4 Ivl=256ms

T:  Bus=01 Lev=01 Prnt=01 Port=00 Cnt=01 Dev#=  2 Spd=480  MxCh= 3
D:  Ver= 2.00 Cls=09(hub  ) Sub=00 Prot=01 MxPS=64 #Cfgs=  1
P:  Vendor=0424 ProdID=2660 Rev= a.a0
C:* #Ifs= 1 Cfg#= 1 Atr=e0 MxPwr=  2mA
I:* If#= 0 Alt= 0 #EPs= 1 Cls=09(hub  ) Sub=00 Prot=00 Driver=hub
E:  Ad=81(I) Atr=03(Int.) MxPS=   1 Ivl=256ms

T:  Bus=01 Lev=02 Prnt=02 Port=00 Cnt=01 Dev#=  3 Spd=480  MxCh= 0
D:  Ver= 2.00 Cls=00(>ifc ) Sub=00 Prot=00 MxPS=64 #Cfgs=  1
P:  Vendor=0424 ProdID=4040 Rev= 2.01
S:  Manufacturer=Generic
S:  Product=Ultra Fast Media Reader
S:  SerialNumber=000000266001
C:* #Ifs= 1 Cfg#= 1 Atr=80 MxPwr= 96mA
I:* If#= 0 Alt= 0 #EPs= 2 Cls=08(stor.) Sub=06 Prot=50 Driver=usb-storage
E:  Ad=02(O) Atr=02(Bulk) MxPS= 512 Ivl=125us
E:  Ad=82(I) Atr=02(Bulk) MxPS= 512 Ivl=0ms
```

即手动拔出SD卡时，`usbmon`中不能检测到相关事件消息，相应的设备节点也并未消失：

```bash
# 拔插SD卡
$ cat /sys/kernel/debug/usb/usbmon/1u

^C
# 已拔出SD卡
$ ls /dev/block/sd*
/dev/block/sda
/dev/block/sdb
/dev/block/sdb1
```

所以需要在`Vold`中实现一个监控线程对存储设备节点间隔操作：

```diff
diff --git a/system/vold/DirectVolume.cpp b/system/vold/DirectVolume.cpp
index 5e0bf01ee4..ebd80f57ee 100755
--- a/system/vold/DirectVolume.cpp
+++ b/system/vold/DirectVolume.cpp
@@ -18,6 +18,7 @@
 #include <stdlib.h>
 #include <string.h>
 #include <errno.h>
+#include <fcntl.h>

 #include <linux/kdev_t.h>

@@ -72,6 +73,35 @@ DirectVolume::~DirectVolume() {
     delete mPaths;
 }

+void *threadMonitor(void *obj)
+{
+	int dosfs;
+	DirectVolume *volume = reinterpret_cast<DirectVolume *>(obj);
+        SLOGD("threadMonitor:%s\n", volume->mDevName);
+	while(volume->mThreadRun){
+		dosfs = open(volume->mDevName, O_RDONLY, 0);
+		if (dosfs < 0) {
+			perror("Can't open");
+			if(errno != ENOMEDIUM){
+				SLOGD("Open fail:%d!\n", errno);
+				//break;
+			}
+			if(volume->mMediaStatus){
+				volume->mMediaStatus = 0;
+    				//setState(Volume::State_NoMedia);
+			}
+		}
+		else{
+			if(volume->mMediaStatus == 0)
+				volume->mMediaStatus = 1;
+			//SLOGD("Open success!\n");
+			close(dosfs);
+		}
+		usleep(1000 * 1000);
+	}
+	return NULL;
+}
+
 int DirectVolume::addPath(const char *path) {
     mPaths->push_back(strdup(path));
     return 0;
```

在上层检测到`sdb`设备被挂载时（插入HUB即创建`/dev/block/sdb`设备直到拔出HUB），创建该线程：

```diff
@@ -193,6 +223,17 @@ void DirectVolume::handleDiskAdded(const char *devpath, NetlinkEvent *evt) {
         mDiskNumParts = 1;
     }

+	const char *p;
+	p = evt->findParam("DEVNAME");
+	if (p && !strcmp(p, "sdb")) {
+		SLOGD("DEVNAME:%s\n", p);
+		mThreadRun = 1;
+		snprintf(mDevName,
+			 sizeof(mDevName), "/dev/block/vold/%d:%d",
+			 mDiskMajor, mDiskMinor);
+		pthread_create(&mThread, NULL, threadMonitor, this);
+	}
+
 #ifdef SUPPORT_LOGICAL_PARTITION
     mPendingPartMap = mDiskNumParts;
 #else
```

在检测到`sdb`移除时（HUB移除），结束该线程：

```diff
@@ -339,9 +397,13 @@ void DirectVolume::handleDiskRemoved(const char *devpath, NetlinkEvent *evt) {
     int minor = atoi(evt->findParam("MINOR"));
     char msg[255];
     bool enabled;
+	const char *p;

     setRemoveState(1);
-
+	p = evt->findParam("DEVNAME");
+	if (p && !strcmp(p, "sdb")) {
+		mThreadRun = 0;
+	}
     if (mVm->shareEnabled(getLabel(), "ums", &enabled) == 0 && enabled) {
         mVm->unshareVolume(getLabel(), "ums");
     }
```

这样，使用`usbmon`即可检测到USB总线上对HUB芯片的定时“扫描”了：

```bash
$ cat /sys/kernel/debug/usb/usbmon/1u
df93f680 227535364 S Bo:1:003:2 -115 31 = 55534243 21000000 00000000 00010600 00000000 00000000 00000000 000000
df93f680 227535493 C Bo:1:003:2 0 31 >
df93f680 227535521 S Bi:1:003:2 -115 13 <
df93f680 227535666 C Bi:1:003:2 0 13 = 55534253 21000000 00000000 01
df93f680 227535692 S Bo:1:003:2 -115 31 = 55534243 22000000 12000000 80010603 00000012 00000000 00000000 000000
df93f680 227535731 C Bo:1:003:2 0 31 >
dbbacb00 227535752 S Bi:1:003:2 -115 18 <
dbbacb00 227535953 C Bi:1:003:2 0 18 = 70000200 0000000a 00000000 3a000000 0000
df93f680 227535981 S Bi:1:003:2 -115 13 <
df93f680 227536111 C Bi:1:003:2 0 13 = 55534253 22000000 00000000 00
```

### 三、兼容无HUB状态

在插入读卡器HUB和不插入的情况下，都需要对U盘的正常挂载。

```conf
/block/sdc      /mnt/media_rw/usb0              vfat    defaults        voldmanaged=usb0:auto   /block/sda
```

如上`fstab`中已兼容了无HUB状态的U盘挂载功能。无HUB情况下直接接入U盘的挂载点是`sda`，有HUB情况下是`sdc`。除此之外，还需要在`recovery`模式中兼容无HUB状态：

```diff
diff --git a/bootable/recovery/roots.cpp b/bootable/recovery/roots.cpp
index 69163dc238..5640f0232a 100755
--- a/bootable/recovery/roots.cpp
+++ b/bootable/recovery/roots.cpp
@@ -21,6 +21,7 @@
 #include <sys/types.h>
 #include <unistd.h>
 #include <ctype.h>
+#include <fcntl.h>

 #include <fs_mgr.h>
 #include "mtdutils/mtdutils.h"
@@ -38,6 +39,45 @@ static struct fstab *fstab = NULL;
 extern struct selabel_handle *sehandle;

 bool boot_mode_is_sdmmc = false;
+
+#if 1
+void rescan_usb_blkname(Volume* v) {
+    if (!strcmp(v->mount_point, "/usb")) {
+        char blkname[100];
+        int j = 0;
+        bool has_found = false;
+
+        for (j = 1; j < 8; j++) {
+            snprintf(blkname, sizeof(blkname), "/dev/block/sdc%d", j);
+            int fd = open(blkname, O_RDONLY, 0);
+            if (fd < 0) {
+                continue;
+            } else {
+                has_found = true;
+                close(fd);
+                break;
+            }
+        }
+        if (!has_found) {
+            for (j = 1; j < 8; j++) {
+                snprintf(blkname, sizeof(blkname), "/dev/block/sda%d", j);
+                int fd = open(blkname, O_RDONLY, 0);
+                if (fd < 0) {
+                    continue;
+                } else {
+                    has_found = true;
+                    close(fd);
+                    break;
+                }
+            }
+        }
+        if (has_found) {
+            strcpy(v->blk_device, blkname);
+        }
+    }
+}
+#endif
+
 void load_volume_table()
```

在`ensure_path_mounted`函数中调用该函数即可实现对U盘的兼容挂载：

```diff
@@ -162,8 +202,10 @@ int ensure_path_mounted(const char* path) {
         // volume is already mounted
         return 0;
     }
  	if(!strcmp(v->mount_point, "/sdcard"))
 		    update_mmcblk_dev_name(v);
+
+    rescan_usb_blkname(v);

     mkdir(v->mount_point, 0755);  // in case it doesn't already exist
```

### 四、SD卡分区读取失败或偶尔不能检测到SD卡插入问题

```text
[  391.366808] sd 2:0:0:1: [sdb] 248320 512-byte logical blocks: (127 MB/121 MiB)
[  391.379429]  sdb: unknown partition table
[  439.415245] sdb: detected capacity change from 127139840 to 0
[  444.428192] sd 2:0:0:1: [sdb] 15499264 512-byte logical blocks: (7.93 GB/7.39 GiB)
[  444.443662]  sdb: sdb1
[  444.662441] FAT-fs (sdb1): Volume was not properly unmounted. Some data may be corrupt. Please run fsck.

[ 1376.394150] sd 2:0:0:1: [sdb] 486998016 512-byte logical blocks: (249 GB/232 GiB)
[ 1376.771178] sd 2:0:0:1: [sdb]
[ 1376.774169] Result: hostbyte=0x00 driverbyte=0x08
[ 1376.778867] sd 2:0:0:1: [sdb]
[ 1376.781956] Sense Key : 0x3 [current]
[ 1376.785704] sd 2:0:0:1: [sdb]
[ 1376.788800] ASC=0x11 ASCQ=0x0
[ 1376.791749] sd 2:0:0:1: [sdb] CDB:
[ 1376.795221] cdb[0]=0x28: 28 00 00 00 00 00 00 00 08 00
[ 1376.800343] Buffer I/O error on dev sdb, logical block 0, async page read
[ 1376.809869] ldm_validate_partition_table(): Disk read failed.
[ 1376.815505]  sdb: unable to read partition table
[ 1394.831247] sdb: detected capacity change from 249342984192 to 0
[ 1397.857400] sd 2:0:0:1: [sdb] 486998016 512-byte logical blocks: (249 GB/232 GiB)
[ 1397.872392]  sdb: sdb1
[ 1397.890779] FAT-fs (sdb1): bogus number of reserved sectors
[ 1397.896379] FAT-fs (sdb1): Can't find a valid FAT filesystem
[ 1397.903719] exFAT-fs (sdb1[8:17]): trying to mount...
[ 1397.912142] exFAT-fs (sdb1[8:17]): set logical sector size  : 512
[ 1397.918277] exFAT-fs (sdb1[8:17]): (bps : 512, spc : 256, data start : 18432, aligned)
[ 1397.926753] exFAT-fs (sdb1[8:17]): detected volume size     : 243466240 KB (disk : 243499008 KB, part : 243466240 KB)
[ 1398.159083] exFAT-fs (sdb1[8:17]): mounted successfully!
```

正常一个8GB的SD卡，有时候读取显示只有128MB且未知分区表，或者干脆显示不能读取分区表，造成SD卡设备识别失败，尤其是在同时插入U盘设备的时候，该现象出现概率大大增加。如果对SD卡拔插不需要太频繁的情况下，上面的方法已经可以接受了。如果考虑到用户体验的话，还需要进行下一步修改。

下载`USBDM`软件并安装，在读卡器上焊接一个`eeprom`，接入到PC上，参照[用户手册][USBDM-USER-GUIDE]，执行如下操作：

![USBDM配置SD卡检测][USBDM-configure]

配置SD卡插入时才创建盘符`sdx`，而不是像之前那样只要插入HUB就立即创建盘符`sdx`，这样基本可以确保每次拔插SD卡时内核都能检测到相关事件，拔插SD卡就相当于拔插U盘。

但是同样的也会存在SD卡、U盘等拔插过于频繁，系统上层没来得及卸载磁盘时导致的SD卡与U盘的盘符是不固定的，这为系统上层判断挂载设备到哪个目录上带来了新的问题。

为解决此类问题，需要在系统上层判断是否为SD卡还是U盘，可以通过USB设备的`VendorID`和`ProductID`来判断当前插入的设备是外接U盘还是SD卡，已知插入SD卡USB设备的`VID`为`0424`，`PID`为`4040`：

```diff
diff --git a/system/vold/DirectVolume.cpp b/system/vold/DirectVolume.cpp
index 0ff5f98..4be52e1 100755
--- a/system/vold/DirectVolume.cpp
+++ b/system/vold/DirectVolume.cpp
@@ -127,14 +127,59 @@ void DirectVolume::handleVolumeUnshared() {
     setState(Volume::State_Idle);
 }

+bool DirectVolume::isSDCardId(const char * devpath) {
+    const char *sdcard_pid = "4040";
+    const char *sdcard_vid = "0424";
+    char pid[8] = {0}, vid[8] = {0};
+    char* pidx = NULL;
+    char syspath[255];
+
+    snprintf(syspath, sizeof(syspath), "/sys%s", devpath);
+    pidx = strstr(syspath, "/host");
+    if (pidx != NULL) {
+        pidx[0] = '\0';
+        pidx = strrchr(syspath, '/');
+        if (pidx != NULL) {
+            char tmppath[255];
+            int fd = -1;
+            pidx[0] = '\0';
+
+            snprintf(tmppath, sizeof(tmppath), "%s/idProduct", syspath);
+            fd = open(tmppath, O_RDONLY, 0);
+            if (fd != -1) {
+                read(fd, pid, 8);
+                SLOGE("%s: %s", __func__, pid);
+                if (strstr(pid, sdcard_pid)) {
+                    snprintf(tmppath, sizeof(tmppath), "%s/idVendor", syspath);
+                    fd = open(tmppath, O_RDONLY, 0);
+                    if (fd != -1) {
+                        read(fd, vid, 8);
+                        SLOGE("%s: %s", __func__, vid);
+                        if (strstr(vid, sdcard_vid)) {
+                            return true;
+                        }
+                    }
+                }
+            }
+        }
+    }
+    return false;
+}
+
 int DirectVolume::handleBlockEvent(NetlinkEvent *evt) {
     const char *dp = evt->findParam("DEVPATH");
+    static char latest_sdcard_block[16] = {0};
+    bool issd = false;
+    int action = evt->getAction();
     int connectedType = 0;
     PathCollection::iterator  it;

+    if (action == NetlinkEvent::NlActionRemove) {
+        if (latest_sdcard_block[0])
+            issd = strstr(dp, latest_sdcard_block);
+    } else {
+        issd = isSDCardId(dp);
+    }

     for (it = mPaths->begin(); it != mPaths->end(); ++it) {
         connectedType++;
-        if (strstr(dp, *it)) {
+        bool is_det_sd = strstr(*it, "sdb"); /* In fstab sdb mean the sdcard mount information */
+        SLOGE("handleBlockEvent: %s: %d/%d", *it, is_det_sd, issd);
+        if ((is_det_sd && issd) || (!is_det_sd && !issd)) {
             /* We can handle this disk */
-            int action = evt->getAction();
             const char *devtype = evt->findParam("DEVTYPE");
             int major = atoi(evt->findParam("MAJOR"));
             int minor = atoi(evt->findParam("MINOR"));
@@ -200,6 +206,10 @@ int DirectVolume::handleBlockEvent(NetlinkEvent *evt) {
                     }
                     setStorageType(connectedType);
                     handleDiskAdded(dp, evt);
+                    if (issd) {
+                        strncpy(latest_sdcard_block, strrchr(dp, '/'), 16);
+                        latest_sdcard_block[4] = '\0';
+                    }
                 } else {
                     if ((mDiskMajor != major) || (mDiskMinor > minor)/* || (mDiskMinor+15 < minor)*/) {
                         break;
@@ -223,6 +233,9 @@ int DirectVolume::handleBlockEvent(NetlinkEvent *evt) {
                     }
                     setStorageType(NULL);
                     handleDiskRemoved(dp, evt);
+                    if (issd) {
+                        latest_sdcard_block[0] = '\0';
+                    }
                 } else {
```

参考资料：

[Android存储系统解析](https://blog.csdn.net/gulinxieying/article/details/78676706)

[Udev triggers are not firing on insert of CF card into USB card reader (anymore)](https://unix.stackexchange.com/questions/38582/udev-triggers-are-not-firing-on-insert-of-cf-card-into-usb-card-reader-anymore)

[SOLVED - Card reader does not recognize card change anymore](https://forums.linuxmint.com/viewtopic.php?t=156758)

[udevil At A Glance](https://ignorantguru.github.io/udevil/)

[usbmon](https://www.kernel.org/doc/Documentation/usb/usbmon.txt)

[udevadm-使用 udev 进行动态内核设备管理](https://documentation.suse.com/zh-cn/sles/15-SP1/html/SLES-all/cha-udev.html)

[USB2660-datasheet]: http://ww1.microchip.com/downloads/en/DeviceDoc/USB2660-USB2660i-Data-Sheet-DS00001931B.pdf
[USBDM-USER-GUIDE]: http://ww1.microchip.com/downloads/en/DeviceDoc/50002293A.pdf
[USBDM-configure]: /images/usbdm-configure.png
