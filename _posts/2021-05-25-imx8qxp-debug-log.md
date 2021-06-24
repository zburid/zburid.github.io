---
layout: post
title:  "iMX8QXP调试笔记"
date:   2021-05-25 10:07:44 +0800
categories: notes
description: "iMX8QXP调试过程笔记--不定期更新"
author: zburid
tags:   iMX8 Android
typora-root-url: ..
show:   true
mermaid: true
---

## 一、基本概念

### 1、SOC 架构


![High-Level Block Diagram][imx8_high_Level_block_diagram]

`iMX8QXP`全称`i.MX 8QuadXPlus`，包含有4个`Cortex-A35`处理器核心（64-bit ARMv8-A），最高运行频率1.2GHz，共用512KB L2 cache。包含有1个`General Purpose Cortex-M4`核心，运行频率266 MHz，控制一组独立外设并可以访问系统总线上的其他设备。

包含一个`SCU`（`System Control Unit`）单元（`Cortex-M4`），用于分配和控制整个芯片资源，其并未开放给用户，只能通过API调用实现相关功能。内有一个`SCS`（`Security Controller Subsystem`），可以为`Secure Boot`功能提供加速。

简化框图如下：

![i.MX 8QuadXPlus/i.MX 8DualXPlus Simplified Block Diagram][imx8_simplified_block_diagram]

参考文档：

《i.MX 8DualX/8DualXPlus/8QuadXPlus Applications Processor Reference Manual.pdf》



### 2、内存映射





参考文档：

《i.MX 8DualX/8DualXPlus/8QuadXPlus Applications Processor Reference Manual.pdf》



### 3、启动流程



参考文档：

《i.MX 8DualX/8DualXPlus/8QuadXPlus Applications Processor Reference Manual.pdf》




### 4、DTS 设备树



```text
imx8qxp-mek-car.dts
`-- imx8qxp-mek-car2.dts
    `-- imx8qxp-mek-rpmsg.dts
        |-- imx8qxp-mek.dts
        |   |-- imx8qxp.dtsi
        |   |   |-- imx8-ss-adma.dtsi
        |   |   |   |-- imx8-ss-audio.dtsi
        |   |   |   `-- imx8-ss-dma.dtsi
        |   |   |-- imx8-ss-security.dtsi
        |   |   |-- imx8-ss-cm40.dtsi
        |   |   |-- imx8-ss-vpu.dtsi
        |   |   |-- imx8-ss-dc0.dtsi
        |   |   |-- imx8-ss-conn.dtsi
        |   |   |-- imx8-ss-ddr.dtsi
        |   |   |-- imx8-ss-lsio.dtsi
        |   |   |-- imx8-ss-hsio.dtsi
        |   |   |-- imx8-ss-img.dtsi
        |   |   |-- imx8-ss-gpu0.dtsi
        |   |   |
        |   |   |-- imx8qxp-ss-adma.dtsi
        |   |   |-- imx8qxp-ss-conn.dtsi
        |   |   |-- imx8qxp-ss-lsio.dtsi
        |   |   |-- imx8qxp-ss-hsio.dtsi
        |   |   |-- imx8qxp-ss-img.dtsi
        |   |   |-- imx8qxp-ss-dc.dtsi
        |   |   |-- imx8qxp-ss-lvds.dtsi
        |   |   `-- imx8qxp-ss-gpu.dtsi
        |   |
        |   `-- imx8x-mek.dtsi
        `-- imx8x-mek-rpmsg.dtsi
```



### 5、测试工具

下载官网上的测试工具源码：

```shell
$ git clone https://source.codeaurora.org/external/imx/imx-test/
$ git switch -c imx_5.4.24_2.1.0
```




### 6、SCU 资源分配



参考文档：






### 7、RPMSG 服务



参考文档：

[iMX8QXP: Use RPMSG to wake up M4 and A35](https://community.nxp.com/docs/DOC-343113)



### 8、EVS 服务

![EVS sequence chart with Cortex-M core and Cortex-A core collaborated together][evs_sequence_chart_between_m4_a35]



参考文档：

《Android_User's_Guide（Rev. android-10.0.0_2.2.0-AUTO）.pdf》

[Android 9.0 Auto及m4 core倒车逻辑–基于imx8qm](https://www.codenong.com/cs105135566/)




## 二、应用案例

### 1、添加烧录分区

* 修改分区表

```diff
diff --git device/fsl/common/partition/device-partitions-13GB-ab.bpt
diff --git device/fsl/common/partition/device-partitions-28GB-ab-dual-bootloader.bpt
+        {
+            "label": "test",
+            "size": "64 MiB",
+            "guid": "auto",
+            "type_guid": "314f99d5-b2bf-4883-8d03-e2f2ce507d6a"
+        },
```

如果不知道`type_guid`字段对应的值是多少，可以先不添加该字段，等到编译完成后在`out`目录下找到相应的分区表文件，从中获取已生成的`type_guid`字段对应的值，并将其添加到源文件。

* 修改烧录脚本

```diff
diff --git device/fsl/common/tools/uuu_imx_android_flash.bat
@@ -25,6 +25,7 @@ set vendor_file=vendor.img
 set product_file=product.img
 set partition_file=partition-table.img
 set super_file=super.img
+set test_file=test.img
 set /A support_dtbo=0
 set /A support_recovery=0
 set /A support_dualslot=0
@@ -707,6 +708,11 @@ if %support_dtbo% == 1 (
     )
 )

+if not [%partition_to_be_flashed:logo=%] == [%partition_to_be_flashed%] (
+    set img_name=%test_file%
+    goto :start_to_flash
+)
+
 if not [%partition_to_be_flashed:gpt=%] == [%partition_to_be_flashed%] (
     set img_name=%partition_file%
     goto :start_to_flash
@@ -744,6 +750,7 @@ if %support_dynamic_partition% == 0 (
     call :flash_partition %vendor_partition% || set /A error_level=1 && goto :exit
     call :flash_partition %product_partition% || set /A error_level=1 && goto :exit
 )
+call :flash_partition %test_partition% || set /A error_level=1 && goto :exit
 call :flash_partition %vbmeta_partition% || set /A error_level=1 && goto :exit
 goto :eof

@@ -756,6 +763,7 @@ set vendor_partition=vendor%1
 set product_partition=product%1
 set vbmeta_partition=vbmeta%1
 set dtbo_partition=dtbo%1
+set test_partition=test
 if %support_dual_bootloader% == 1 set dual_bootloader_partition=bootloader%1
 goto :eof
```

在`uuu_imx_android_flash.bat`脚本中添加对新添加分区`test`分区的支持。如果是`Linux`环境下，也需要按照同样的需求修改`uuu_imx_android_flash.sh`脚本。

* 检验新分区

采用一个图片文件作为分区镜像文件，将其文件名及后缀改为`test.img`，并执行`uuu_imx_android_flash.bat`脚本烧录系统。镜像数据如下：

```shell
$ hexdump -n 32 -C ./test.img
00000000  ff d8 ff ee 00 0e 41 64  6f 62 65 00 64 00 00 00  |......Adobe.d...|
00000010  00 00 ff db 00 43 00 08  06 06 07 06 05 08 07 07  |.....C..........|
```

重启进入`bootloader`中读取分区数据：

```text
=> mmc list
FSL_SDHC: 0 (eMMC)
=> mmc part
Partition Map for MMC device 0  --   Partition Type: EFI

Part    Start LBA       End LBA         Name
        Attributes
        Type GUID
        Partition GUID
...
 12     0x00650000      0x0066ffff      "test"
        attrs:  0x0000000000000000
        type:   314f99d5-b2bf-4883-8d03-e2f2ce507d6a
        guid:   3ee99210-9bc5-4957-8b8b-f8b72d413da1
=> read mmc 0 0xFA000000 0x00650000 0x200
=> md.b 0xFA000000 0x20
e0000000: ff d8 ff ee 00 0e 41 64 6f 62 65 00 64 00 00 00    ......Adobe.d...
e0000010: 00 00 ff db 00 43 00 08 06 06 07 06 05 08 07 07    .....C..........
```

注意读取分区数据存放的内存地址，访问未赋予权限的地址会造成异常错误。

进入`Android`系统中读取分区节点数据：

```shell
$ head -c 32 /dev/block/mmcblk0p12 | hexdump
00000000: FF D8 FF EE 00 0E 41 64 - 6F 62 65 00 64 00 00 00 |      Adobe d   |
00000010: 00 00 FF DB 00 43 00 08 - 06 06 07 06 05 08 07 07 |     C          |
```

当应用程序需要修改分区数据时，可以直接通过对`mmcblk`节点写操作即可。

参考文档：

[Android EMMC中添加分区并开机自动挂载方法](https://blog.csdn.net/eurphan_y/article/details/106861076)



### 2、M4绘制开机动画

方案：把很多张`JPEG`图片放到`EMMC`，开机等到`A35`核运行起来后，把这些图片数据复制到`shard memory`，然后`M4`核从`shared memeory`去拿这些图片，并用`JPEG decoder`一个一个解压缩，达到动画的效果。

* 测试`JPEG decoder`

按照官方提供的参考例程，添加相关修改到`M4`代码中去，需要确保的是`APP_InitDisplay`调用之前`s_showJpeg`已经设置为`true`：

```cpp
            if (!s_displayInit)
            {
#ifdef APP_SHOW_JPEG
                s_showJpeg = true;
#endif
                ...
                APP_InitDisplay((uint32_t)s_graphBuffer[s_graphIndex], (uint32_t)s_overlayBuffer, APP_DisplayFrameDoneCallback);
                ...
            }
```

除此之外，还需要在`scfw`中添加`M4`对`JPEG decoder`的访问权限：

```diff
diff --git vendor/nxp/fsl-proprietary/uboot-firmware/imx8q_car/board-imx8qxp.c

@@ -708,6 +708,11 @@ sc_err_t mark_shared_resources(sc_rm_pt_t pt_src, sc_bool_t movable)
     BRD_ERR(rm_set_resource_movable(pt_src, SC_R_ISI_CH0,
         SC_R_ISI_CH0, movable));

+    BRD_ERR(rm_set_resource_movable(pt_src, SC_R_MJPEG_DEC_MP,
+        SC_R_MJPEG_DEC_MP, movable));
+    BRD_ERR(rm_set_resource_movable(pt_src, SC_R_MJPEG_DEC_S0,
+        SC_R_MJPEG_DEC_S0, movable));
+
     /* Move some pads not in the M4_0 subsystem */
     BRD_ERR(rm_set_pad_movable(pt_src, SC_P_MIPI_CSI0_GPIO0_00,
         SC_P_MIPI_CSI0_MCLK_OUT, movable));
```

如果需要在`M4`使用完`JPEG decoder`释放资源的话，可以添加：

```diff
diff --git vendor/nxp/mcu-sdk-auto/SDK_MEK-MIMX8QX/boards/mekmimx8qx/demo_apps/rear_view_camera/isi_board.c

@@ -1866,6 +1866,9 @@ void SOC_AssignDisplayCamera(sc_rm_pt_t pt)
     sc_rm_set_resource_movable(ipc, SC_R_ISI_CH0, SC_R_ISI_CH0, SC_TRUE);

+    sc_rm_set_resource_movable(ipc, SC_R_MJPEG_DEC_MP, SC_R_MJPEG_DEC_MP, SC_TRUE);
+    sc_rm_set_resource_movable(ipc, SC_R_MJPEG_DEC_S0, SC_R_MJPEG_DEC_S0, SC_TRUE);
+
     /* Move some pads not in the M4_0 subsystem */
```

将测试图片添加到`bootloader`烧录文件中：

```diff
diff --git vendor/nxp-opensource/imx-mkimage/iMX8QX/scripts/android.mak
@@ -1,8 +1,14 @@
 flash_b0_all_ddr: $(MKIMG) $(AHAB_IMG) scfw_tcm.bin u-boot-atf.bin m4_image.bin
-       ./$(MKIMG) -soc QX -rev B0 -append $(AHAB_IMG) -c -scfw scfw_tcm.bin -ap u-boot-atf.bin a35 0x80000000 -m4 m4_image.bin 0 0x88000000 -out flash.bin
+       ./$(MKIMG) -soc QX -rev B0 -append $(AHAB_IMG) -c -scfw scfw_tcm.bin -ap u-boot-atf.bin a35 0x80000000 -m4 m4_image.bin 0 0x88000000 --data demo_rgb.jpg 0x89F00000 --data demo_rgb2.jpg 0x89F40000 -out flash.bin

 flash_all_spl_container_ddr: $(MKIMG) $(AHAB_IMG) scfw_tcm.bin u-boot-atf-container.img m4_image.bin u-boot-spl.bin
-       ./$(MKIMG) -soc QX -rev B0 -append $(AHAB_IMG) -c -scfw scfw_tcm.bin -ap u-boot-spl.bin a35 0x00100000 -m4 m4_image.bin 0 0x88000000 -out flash.bin
+       ./$(MKIMG) -soc QX -rev B0 -append $(AHAB_IMG) -c -scfw scfw_tcm.bin -ap u-boot-spl.bin a35 0x00100000 -m4 m4_image.bin 0 0x88000000 --data demo_rgb.jpg 0x89F00000 --data demo_rgb2.jpg 0x89F08000 -out flash.bin
        cp flash.bin boot-spl-container.img
@@ -10,7 +16,10 @@ flash_all_spl_container_ddr: $(MKIMG) $(AHAB_IMG) scfw_tcm.bin u-boot-atf-contai
                    dd if=u-boot-atf-container.img of=flash.bin bs=1K seek=$$pad_cnt; \

 flash_all_spl_container_ddr_car: $(MKIMG) $(AHAB_IMG) scfw_tcm.bin u-boot-atf-container.img m4_image.bin u-boot-spl.bin
-       ./$(MKIMG) -soc QX -rev B0 -append $(AHAB_IMG) -c -flags 0x01200000 -scfw scfw_tcm.bin -ap u-boot-spl.bin a35 0x00100000 -p3 -m4 m4_image.bin 0 0x88000000 -out flash.bin
+       ./$(MKIMG) -soc QX -rev B0 -append $(AHAB_IMG) -c -flags 0x01200000 -scfw scfw_tcm.bin -ap u-boot-spl.bin a35 0x00100000 -p3 -m4 m4_image.bin 0 0x88000000 --data demo_rgb.jpg 0x89F00000 --data demo_rgb2.jpg 0x89F40000 -out flash.bin
        cp flash.bin boot-spl-container.img
```

默认的`M4`保留内存地址是`0x8800_0000 ~ 0x8FFF_FFFF`：

```dtsi
// vendor/nxp-opensource/kernel_imx/arch/arm64/boot/dts/freescale/imx8x-mek.dtsi
m4_reserved: m4@0x88000000 {
        no-map;
        reg = <0 0x88000000 0 0x8000000>;
};
```

对于临时测试，可以将图片地址放在`m4_reserved`内存范围内，以免因为`SCU`权限问题，造成`JPEG decoder`不能正常解码显示（解码成功会进入中断服务函数），或者`M4`代码访问图片内存地址时会造成`M4`核心异常。



* 测试`RPMSG`共享内存

按照官方提供的参考例程，添加相关修改到`M4/Bootloader/DTS`中去，需要确保的是`APP_SRTM_StartCommunication`在`M4`调用之前，`Bootloader`已经初始化好设置的共享内存：

```diff
diff --git vendor/nxp/mcu-sdk-auto/SDK_MEK-MIMX8QX/boards/mekmimx8qx/demo_apps/rear_view_camera/automotive.c
@@ -100,6 +103,8 @@ static void ap_power_monitor_task(void *pvParameters)
     ap_power_state_t ap_power;
     uint8_t reqData[SRTM_USER_DATA_LENGTH];

+    vTaskDelay(pdMS_TO_TICKS(4000));
     APP_SRTM_StartCommunication();

diff --git vendor/nxp/mcu-sdk-auto/SDK_MEK-MIMX8QX/boards/mekmimx8qx/demo_apps/rear_view_camera/app_srtm.c
@@ -550,6 +587,7 @@ static void SRTM_MonitorTask(void *pvParameters)
                 /* Remove peer core from dispatcher */
                 APP_SRTM_DeinitPeerCore();

+                vTaskDelay(pdMS_TO_TICKS(4000));
                 /* Restore srtmState to Run. */
                 srtmState = APP_SRTM_StateRun;
```

通过增加延时的方法解决`SRTM`启动过快导致的`M4`核心卡死的问题。



* 实现开机动画

首先需要生成可用格式的`JPEG`文件。可以通过`PC`生成`RGB`数据，然后由`imx-test/mxc_jpeg_test/encoder_test`工具将其转换为可用的`RGB24`格式的`JPEG`文件。

在使用该工具值前，需要确保`Android/Linux`下生成了`JPEG Encoder`设备节点：

```diff
diff --git vendor/nxp-opensource/kernel_imx/arch/arm64/boot/dts/freescale/imx8qxp-mek-car2.dts
 &jpegdec {
-       status = "disabled";
+       status = "okay";
 };

 &jpegenc {
-       status = "disabled";
+       status = "okay";
 };
```

编译生成烧录后手动安装驱动程序，不同环境下生成的`V4L2`设备节点名可能会变化：

```shell
$ insmod /vendor/lib/modules/mxc-jpeg-encdec.ko
[   57.349270] mxc-jpeg 58400000.jpegdec: decoder device registered as /dev/video1 (81,3)
[   57.376725] mxc-jpeg 58450000.jpegenc: encoder device registered as /dev/video2 (81,4)
```

确认`encoder_test`工具可用，可以将相关源码复制到`external`下，添加`Android.mk`编译生成测试工具。

将`JPEG`文件转换为`RGB`数据，注意`RGB`数据保存时的字节序是`bgr`：

```shell
ls -1 *.jpg | xargs -n 1 bash -c 'convert -depth 8 "$0" bgr:"${0%.jpg}.rgb"'
```

将`RGB`数据转换为可用格式的`JPEG`文件，通常采用`RGB24`格式：

```shell
ls -1 *.rgb | xargs -n 1 sh -c 'encoder_test -d /dev/video2 -f "$0" -w 640 -h 480 -p rgb24 && mv -f outfile.jpeg "${0%.rgb}.jpg"'
```

通常需要将`RGB`数据`push`到`Android`系统中去，然后执行命令生成`JPEG`文件并`pull`出来。

然后编写打包`JPEG`文件到镜像的脚本，生成固定格式的镜像文件：

```text
+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
| 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | A | B | C | D | E | F |
+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
|          Magic  Code          | Nums  | Flags | Image Checksum|
+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
|                                                               |
...        Pictures Data One by One with order & align        ...
|                                                               |
+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
```

通常需要设置`JPEG`文件对齐为固定长度的形式，以免出现问题。其余均参考添加分区的方法实现即可。

最后设置从`Bootloader`中加载分区镜像到共享内存，通过调用`do_raw_read`方法来实现这一功能：

```diff
diff --git vendor/nxp-opensource/uboot-imx/common/autoboot.c

+static int initr_mmc_logo(void)
+{
+       char * argv[6];
+
+       puts("Loading EMMC boot animation to share memory\r\n");
+       /* Equals to cmd: => read mmc 0 0xF6500000 0x00650000 0x3D800 */
+       argv[0] = "read"; /* not care */
+       argv[1] = "mmc";
+       argv[2] = "0";
+       argv[3] = "0xF6500000";
+       argv[4] = "0x00650000";
+       argv[5] = "0x3D800"; /* size = block_cnt * 512 = 123MB */
+       do_raw_read(NULL, 0, 6, argv);
+       return 0;
+}

@@ -311,7 +327,10 @@ const char *bootdelay_process(void)
        } else {
                printf("Normal Boot\n");
+#ifdef CONFIG_MMC
+               initr_mmc_logo();
+#endif
        }
 #endif
```

剩下的就是根据需要在`M4`中配置图片解码的帧率等操作了。



参考文档：



[iMX8QXP: Use JPEG decoder in M4 SDK](https://community.nxp.com/t5/i-MX-Processors-Knowledge-Base/iMX8QXP-Use-JPEG-decoder-in-M4-SDK/ta-p/1101663)

[Add a new shared memory region on Android Auto P9.0.0_GA2.1.0 BSP](https://community.nxp.com/t5/i-MX-Processors-Knowledge-Base/Add-a-new-shared-memory-region-on-Android-Auto-P9-0-0-GA2-1-0/ta-p/1124239)



[imx8_simplified_block_diagram]: /images/imx8_simplified_block_diagram.png
[imx8_high_Level_block_diagram]: /images/imx8_high_Level_block_diagram.png
[evs_sequence_chart_between_m4_a35]: /images/evs_sequence_chart.png
