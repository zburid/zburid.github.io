---
layout: post
title:  "HUB与读卡器芯片USB2660调试"
date:   2020-09-24 13:19:58 +0800
categories: notes
description: "Android4.4平台下HUB与读卡器芯片USB2660调试记录"
author: zburid
tags:   HUB 读卡器 Android USB2660
typora-root-url: ..
---

### 一、Vold实现U盘与SD卡挂载

参考资料：
[Android存储系统解析](https://blog.csdn.net/gulinxieying/article/details/78676706)

[Udev triggers are not firing on insert of CF card into USB card reader (anymore)](https://unix.stackexchange.com/questions/38582/udev-triggers-are-not-firing-on-insert-of-cf-card-into-usb-card-reader-anymore)

[SOLVED - Card reader does not recognize card change anymore](https://forums.linuxmint.com/viewtopic.php?t=156758)

[udevil At A Glance](https://ignorantguru.github.io/udevil/)

[usbmon](https://www.kernel.org/doc/Documentation/usb/usbmon.txt)

[udevadm-使用 udev 进行动态内核设备管理](https://documentation.suse.com/zh-cn/sles/15-SP1/html/SLES-all/cha-udev.html)

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

由于`DEVPATH`通常都是如下格式：
```conf
/devices/virtual/block/loop6
/devices/xxx-sdhc.3/mmc_host/mmc0/mmc0:0001/block/mmcblk0/mmcblk0boot1
/devices/dwc_otg/usb1/1-1/1-1.2/1-1.2:1.0/host1/target1:0:0/1:0:0:0/block/sdc
/devices/dwc_otg/usb1/1-1/1-1.1/1-1.1:1.0/host0/target0:0:0/0:0:0:1/block/sdb/sdb1
```
因此当HUB接入USB总线时，SD卡与U盘的`DEVPATH`都是以`/devices/dwc_otg/`开头的格式，在`fstab`列表中无法实现区分。而采用`/block/sdb`的形式的话，需要更改`DirectVolume::handleBlockEvent`函数如下：
```diff
- if (!strncmp(dp, *it, strlen(*it))) { // 判断fstab配置字符串是否与DEVPATH最前相等
+ if (strstr(dp, *it)) {                // 判断fstab配置字符串出现在DEVPATH里面
```



### 二、SD卡热插拔检测



### 三、兼容非HUB状态
