---
layout: post
title:  "修改Android串号"
date:   2018-06-25 09:13:02 +0800
categories: notes
description: "修改默认的Android串号为EMMC串号的组合"
author: zburid
tags:   Android EMMC 嵌入式 串号
typora-root-url: ..
show:   true
---

### 一、为什么需要串号

因为某些软件的安装需要`License`，是根据不同的系统的`SN`号来判定的，`SN`号也可以帮助后台管理设备、分析问题和`OTA`升级等。获取`SN`号的方法：

```bash
$ cat /proc/cmdline
vmalloc=480M console=ttyS0,115200n8 androidboot.console=ttyS0 androidboot.serialno=00001806171549320001 androidboot.wifimac= androidboot.btaddr=E470B8A93A43 androidboot.mode=emmc androidboot.dignostic= androidboot.memtype=2 androidboot.qb_prebuilt_mode=disable resume=/dev/block/platform/bdm/by-name/snapshot androidboot.hardware=xxxxxxx vmalloc=480M
```

其中`androidboot.serialno`就是系统串号，通常每一台设备的串号都是不一样的。

### 二、系统获取串号方式

#### 1、应用层中`serialno`的产生方式

在源码最可能出现`androidboot.serialno`的目录下比如`system/`、`device/`进行搜索：

```bash
$ cd /path/to/sdk/xxxx
$ grep -rn "androidboot.serialno"
```

在`/path/to/sdk/system/core/init/init.c`中找到函数如下：

```cpp
static void import_kernel_nv(char *name, int for_emulator)
{
    char *value = strchr(name, '=');
    int name_len = strlen(name);

    if (value == 0) return;
    *value++ = 0;
    if (name_len == 0) return;

    if (for_emulator) {
        /* in the emulator, export any kernel option with the
         * ro.kernel. prefix */
        char buff[PROP_NAME_MAX];
        int len = snprintf( buff, sizeof(buff), "ro.kernel.%s", name );

        if (len < (int)sizeof(buff))
            property_set( buff, value );
        return;
    }

    if (!strcmp(name,"qemu")) {
        strlcpy(qemu, value, sizeof(qemu));
    } else if (!strncmp(name, "androidboot.", 12) && name_len > 12) {
        const char *boot_prop_name = name + 12;
        char prop[PROP_NAME_MAX];
        int cnt;

        cnt = snprintf(prop, sizeof(prop), "ro.boot.%s", boot_prop_name);
        if (cnt < PROP_NAME_MAX)
            property_set(prop, value);
    }
}
static void export_kernel_boot_props(void)
{
    char tmp[PROP_VALUE_MAX];
    int ret;
    int pval;
    unsigned i;
    struct {
        const char *src_prop;
        const char *dest_prop;
        const char *def_val;
    } prop_map[] = {
        { "ro.boot.serialno", "ro.serialno", "", },
        { "ro.boot.mode", "ro.bootmode", "unknown", },
        { "ro.boot.baseband", "ro.baseband", "unknown", },
        { "ro.boot.bootloader", "ro.bootloader", "unknown", },
        { "ro.boot.btaddr", "ro.btaddr", "unknown", },
        { "ro.boot.dignostic", "ro.dignostic", "unknown", },
        { "ro.boot.qb_prebuilt_mode", "ro.qb_prebuilt_mode", "unknown", },
    };

    for (i = 0; i < ARRAY_SIZE(prop_map); i++) {
        ret = property_get(prop_map[i].src_prop, tmp);
        if (ret > 0)
            property_set(prop_map[i].dest_prop, tmp);
        else
            property_set(prop_map[i].dest_prop, prop_map[i].def_val);
    }

    ret = property_get("ro.boot.console", tmp);
    if (ret)
        strlcpy(console, tmp, sizeof(console));

    /* save a copy for init's usage during boot */
    property_get("ro.bootmode", tmp);
    strlcpy(bootmode, tmp, sizeof(bootmode));
    pval = property_get("ro.boot.dignostic",tmp);
    if (pval) {
        strlcpy(dignostic_mode, pval, sizeof(dignostic_mode));
    }

    ret = property_get("ro.boot.qb_prebuilt_mode", tmp);
    if (ret)
      strlcpy(qb_prebuilt_mode, tmp, sizeof(qb_prebuilt_mode));

    /* if this was given on kernel command line, override what we read
     * before (e.g. from /proc/cpuinfo), if anything */
    ret = property_get("ro.boot.hardware", tmp);
    if (ret)
        strlcpy(hardware, tmp, sizeof(hardware));
    property_set("ro.hardware", hardware);

    snprintf(tmp, PROP_VALUE_MAX, "%d", revision);
    property_set("ro.revision", tmp);

    /* TODO: these are obsolete. We should delete them */
    if (!strcmp(dignostic_mode,"xxx_factory"))
        property_set("ro.xxx.factorytest", "1");
    if (!strcmp(bootmode,"factory"))
        property_set("ro.factorytest", "1");
    else if (!strcmp(bootmode,"factory2"))
        property_set("ro.factorytest", "2");
    else
        property_set("ro.factorytest", "0");

    if (!strcmp(qb_prebuilt_mode, "enable")) property_set("ro.xxx.qb_prebuilt_mode", "1");
    else property_set("ro.xxx.qb_prebuilt_mode", "0");

    property_set("ro.rotation.block180", block180);
    property_set("ro.hardware.nfc",hardwareNfc); // pn544
}

static void process_kernel_cmdline(void)
{
    /* don't expose the raw commandline to nonpriv processes */
    chmod("/proc/cmdline", 0444);

    /* first pass does the common stuff, and finds if we are in qemu.
     * second pass is only necessary for qemu to export all kernel params
     * as props.
     */
    import_kernel_cmdline(0, import_kernel_nv);
    if (qemu[0])
        import_kernel_cmdline(1, import_kernel_nv);

    /* now propogate the info given on command line to internal variables
     * used by init as well as the current required properties
     */
    export_kernel_boot_props();
}
```

可以发现`process_kernel_cmdline`更改`/proc/cmdline`文件访问权限后，将`import_kernel_nv`作为回调函数传入`import_kernel_cmdline`函数作为解析方法，最后由`export_kernel_boot_props`获得最终的组合参数。
在`/path/to/sdk/system/core/init/util.c`中找到`import_kernel_cmdline`函数：

```cpp
void import_kernel_cmdline(int in_qemu,
                           void (*import_kernel_nv)(char *name, int in_qemu))
{
    char cmdline[1024];
    char *ptr;
    int fd;

    fd = open("/proc/cmdline", O_RDONLY);
    if (fd >= 0) {
        int n = read(fd, cmdline, 1023);
        if (n < 0) n = 0;

        /* get rid of trailing newline, it happens */
        if (n > 0 && cmdline[n-1] == '\n') n--;

        cmdline[n] = 0;
        close(fd);
    } else {
        cmdline[0] = 0;
    }

    ptr = cmdline;
    while (ptr && *ptr) {
        char *x = strchr(ptr, ' ');
        if (x != 0) *x++ = 0;
        import_kernel_nv(ptr, in_qemu);
        ptr = x;
    }
}
```

应用层上看最终的数据来源是`/proc/cmdline`文件，是由`bootloader`传递给`kernel`的。

#### 2、底层中`serialno`的产生方式

在源码最可能出现`androidboot.serialno`的目录下比如`hardware/`、`bootloader/`进行搜索：

```bash
$ cd /path/to/sdk/xxxx
$ grep -rn "androidboot.serialno"
```

在`/path/to/sdk/bootable/bootloader/lk/target/xxxxxxx-lcn/init.c`中找到函数如下：

```cpp
static int board_get_serialno(char *serialno)
{
    int n,i;
    char temp[32];

#if _EMMC_BOOT
    if (target_is_emmc_boot())
        n = get_emmc_serial(temp);
    else
#endif
        n = NAND_GetSerialNumber(temp, 32);
    for (i=0; i<4; i++)     // 4 = custon field(2) + product number(2)
        *serialno++ = temp[i];
    for (i=16; i<32; i++)   // 16 = time(12) + serial count(4)
        *serialno++ = temp[i];
    *serialno = '\0';
    return strlen(serialno);
}

void target_cmdline_serialno(char *cmdline)
{
    char s[128];
    char s2[64];

    board_get_serialno(s2);
#if _EMMC_BOOT
    if(boot_into_chrome)
        sprintf(s, " root=/dev/mmcblk0p3 rw rootfstype=ext2 rootwait noinitrd", s2);
    else
        sprintf(s, " androidboot.serialno=%s", s2);
#else
    sprintf(s, " androidboot.serialno=%s", s2);
#endif
    strcat(cmdline, s);
}
```

可以看到`target_cmdline_serialno`组合了`/proc/cmdline`中`androidboot.serialno`字符串，通过`board_get_serialno`获取原始值，`board_get_serialno`又是通过读取`EMMC`或者`NAND`的串号而得来的。
查找到这两个函数：

```cpp
// path/to/sdk/bootable/bootloader/lk/platform/xxx_shared/nand_drv_dummy.c
int NAND_GetSerialNumber( unsigned char *pucSN, unsigned int uiSize )
{
    return 0;
}

// path/to/sdk/bootable/bootloader/lk/platform/xxx_shared/emmc.c
// path/to/sdk/bootable/bootloader/lk/u-boot/drivers/soc/xxxxxxxxx/sdmmc/emmc.c
int get_emmc_serial(char* Serial)
{
    ioctl_diskinfo_t disk_info;
    ioctl_diskrwpage_t bootCodeRead;
    BOOTSD_Header_Info_T readData;
    int res;
    int i;

    if(DISK_Ioctl(DISK_DEVICE_TRIFLASH, DEV_GET_DISKINFO , (void*)&disk_info) <0)
        return -1;

    if(disk_info.sector_size != 512)
        return -1;

    bootCodeRead.start_page = BOOTSD_GetHeaderAddr(0);
    bootCodeRead.rw_size = 1;
    bootCodeRead.buff  = (unsigned char *)&readData;
    bootCodeRead.boot_partition  = 0;
    res = DISK_Ioctl(DISK_DEVICE_TRIFLASH, DEV_BOOTCODE_READ_PAGE, (void*)&bootCodeRead);
    if(res !=0) return -1;

    for(i=0; i<16; i++)
        Serial[i] = readData.ucSerialNum[i];
    for(i=16 ; i<32; i++)
        Serial[i]= readData.ucSerialNum[i+16];

    return 0;
}
```

从上述代码中可以看出，目前获取的`EMMC`串号是通过读取`EMMC`中某一块分区中的数据而得到的。如果对`EMMC`进行擦除操作，那么就会造成之前的串号丢失的情况发生。

为此，我们修改这个函数，通过组合`EMMC`的串号来作为系统串号，如下：

```cpp
int get_emmc_serial(char* Serial)
{
    if (Serial == NULL)
        return -1;
    if(DISK_Ioctl(DISK_DEVICE_TRIFLASH, DEV_SERIAL_PROCESS , (void*)Serial) < 0)
        return -1;
    return 0;
}
```

```cpp
// bootable/bootloader/lk/platform/xxx_shared/sd_memory.c
int BOOTSD_Ioctl(int function, void *param)
{
    ... ...
    switch(function)
    {
        ... ...
        case DEV_SERIAL_PROCESS:
            {
                char *pSNbuf = (char*)param;

                res = SD_BUS_GetSN(iSlotIndex, pSNbuf);
                break;
            }
        ... ...
    }
    ... ...
}
```

根据需求组合`Sandisk`的`CID`数据：

```cpp
// bootable/bootloader/lk/platform/xxx_shared/sd_bus.c
int SD_BUS_GetSN(int iSlotIndex, char* cPSNBuf)
{
    PSD_SLOT_T pSlot;
    if (SD_BUS_SlotIndex_Validate(iSlotIndex)==0)
        return 0;
    pSlot = &sSD_BUS_Slot[iSlotIndex];

    if (SD_SLOT_IsCardDetected(pSlot))              // For Sandisk Chips
    {
        sprintf(cPSNBuf, "0%c%c%c%08X%04X%c%c%c%c%04X%08X",
                (char)pSlot->stCID.MID,             // 'E'
                (char)pSlot->stCID.PNM_U,           // 'D'
                (char)((pSlot->stCID.PNM_L >>24)-1),// 'F' = 'G'-1
                pSlot->stCID.OID,                   // 0x0100
                pSlot->stCID.CRC,                   // 0x00
                (char)(pSlot->stCID.PNM_L >> 16),   // '4'
                (char)(pSlot->stCID.PNM_L >> 8),    // '0'
                (char)(pSlot->stCID.PNM_L >> 0),    // '6'
                (char)pSlot->stCID.PRV,             // '4'
                pSlot->stCID.MDT,                   // 0x0555
                pSlot->stCID.PSN);                  // 0x010580B2
        return 0;
    }
    else
    {
        sprintf(cPSNBuf, "%08X%08X%08X%08X", 0, 0, 0, 0);
        return -1;
    }
}
```

根据`EMMC`说明书可知其中参数的含义：

![EMMC CID寄存器值说明][emmc-cid-register]

`Linux`命令行获取`EMMC`的`CID`方法：

```bash
root@vendor:/ # cat /sys/block/mmcblk0/../../cid
45010044473430363401fb74b2055500
root@vendor:/ # cat /sys/block/mmcblk0/device/serial
0xfb74b205
```

[emmc-cid-register]: /images/emmc-cid-register.png

