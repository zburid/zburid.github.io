---
layout: post
title:  "WiFi-BT模块移植笔记"
date:   2021-01-11 13:34:20 +0800
categories: notes
description: "顾凯BA440蓝牙WiFi模块驱动移植过程记录"
author: zburid
tags:   WiFi 蓝牙 模块 驱动 移植 iMX8
typora-root-url: ..
show:   true
mermaid: true
---

## 一. 模块厂商

### 1. 模块简介
**BA440**是由[深圳市顾凯信息技术有限公司](http://goodocom.com/)设计研发的一款车规级蓝牙WIFI模块。WIFI方面，支持最高433.3Mbps数据传输率，支持IEEE 802.11 a/g/b/n，支持2.4GHz和5GHz频段。蓝牙方面，支持蓝牙版本BLE4.2+3.0+2.1。接口方面，支持SDIO3.0，支持高达4Mbps串口速率。

![BA440模块图][BA440_module]

![BA440版图][BA440_top_layout]

该模块其实是采用博通（`Broadcom`）的方案，其WIFI驱动程序`bcmdhd`也是从博通的驱动修改而来的。后期博通的物联网业务卖给了赛普拉斯（`Cypress`），其生成的驱动程序也变成了`cywdhd`，但并不影响正常工作。

### 2. 通用前提

![BA440接口图][BA440_interface_diagram]

![BA440原理图][BA440_schematic_diagram]

1. SOC在上电后加载驱动程序，驱动程序在与模块通信成功后加载模块的固件到模块的内存中去，模块从加载的固件处启动。

2. WIFI的通信接口是SDIO，蓝牙的通信接口是UART（硬件流控），PCM（I2S）是用于蓝牙电话功能的，蓝牙音乐通过UART流通。

3. BA440通用模块需要外接IPEX座子的天线，如需使用板载天线需要购买定制化版本的模块。

4. 模块需要外部提供一个32.768KHz的时钟信号，该信号可以通过外部有源晶振提供，或者SOC输出。

5. 一般情况下SOC使用2个控制脚和一个中断脚，分别是WIFI_EN，BT_EN，WIFI_IRQ，两个控制脚一般在Linux中设计为两个RFKILL设备，如果没有WIFI_IRQ引脚的话，需要在驱动实现轮询配置。

## 二. Wifi 驱动添加

### 1. MMC驱动修改与确认

在添加驱动之前，需要确认MMC接口（SDIO）是否可用，BCMDHD引用MMC相关的函数一般有两个：

```h
void wifi_card_detect(bool on);             // 用于回调MMC扫描当前SDIO总线上的设备
int sdio_reset_comm(struct mmc_card *card); // 用于强行复位当前SDIO总线
```

在Android P版本上这两个函数是已经实现了的，但当前的  SDK 2.2 到 2.5 版本是没有的，所以需要人工添加进去：

```diff
--- a/android_build/vendor/nxp-opensource/kernel_imx/drivers/mmc/host/sdhci-esdhc-imx.c
+++ b/android_build/vendor/nxp-opensource/kernel_imx/drivers/mmc/host/sdhci-esdhc-imx.c

+static struct mmc_host *wifi_mmc_host;
+void wifi_card_detect(bool on)
+{
+ if (!wifi_mmc_host) {
+	  WARN_ON(!wifi_mmc_host);
+	  return;
+ }
+ printk("wifi_mmc_host->rescan_disablble = %d on = %d\n", wifi_mmc_host->rescan_disable, on);
+	if (on) {
+		printk("%s: now %p host mmc_detect_change\n", __func__, wifi_mmc_host);
+		mmc_detect_change(wifi_mmc_host, 0);
+	} else {
+		if (wifi_mmc_host->card)
+		{
+			printk("%s: now %p card mmc_sdio_force_remove\n", __func__, wifi_mmc_host->card);
+			mmc_sdio_force_remove(wifi_mmc_host);
+		}
+	}
+}
+EXPORT_SYMBOL(wifi_card_detect);
```

注意`wifi_card_detect`中必须要先检测`wifi_mmc_host`是否为`NULL`，否则如果在DTS中未配置相应的SDHC设备的情况下，每次加载驱动程序时都会导致内核崩溃。

```diff
--- a/android_build/vendor/nxp-opensource/kernel_imx/drivers/mmc/core/sdio.c
+++ b/android_build/vendor/nxp-opensource/kernel_imx/drivers/mmc/core/sdio.c

+int sdio_reset_comm(struct mmc_card *card)
+{
+	struct mmc_host *host = card->host;
+	u32 ocr;
+	u32 rocr;
+	int err;
+
+	mmc_claim_host(host);
+	mmc_go_idle(host);
+	mmc_set_clock(host, host->f_min);
+	err = mmc_send_io_op_cond(host, 0, &ocr);
+	if (err)
+		goto err;
+	rocr = mmc_select_voltage(host, ocr);
+	if (!rocr) {
+		err = -EINVAL;
+		goto err;
+	}
+	err = mmc_sdio_init_card(host, rocr, card);
+	if (err)
+		goto err;
+	mmc_release_host(host);
+	return 0;
+err:
+	pr_err("%s: Error resetting SDIO communications (%d)\n",
+		mmc_hostname(host), err);
+	mmc_release_host(host);
+	return err;
+}
+EXPORT_SYMBOL(sdio_reset_comm);

+void mmc_sdio_force_remove(struct mmc_host *host)
+{
+	mmc_sdio_remove(host);
+
+	mmc_claim_host(host);
+	mmc_detach_bus(host);
+	mmc_power_off(host);
+	mmc_release_host(host);
+}
+EXPORT_SYMBOL_GPL(mmc_sdio_force_remove);
```

修改DTS文件如下：

```diff
--- a/android_build/vendor/nxp-opensource/kernel_imx/arch/arm64/boot/dts/freescale/imx8x-mek.dtsi
+++ b/android_build/vendor/nxp-opensource/kernel_imx/arch/arm64/boot/dts/freescale/imx8x-mek.dtsi

@@ -1014,8 +1025,15 @@
&usdhc2 {
 	pinctrl-2 = <&pinctrl_usdhc2>, <&pinctrl_usdhc2_gpio>;
 	bus-width = <4>;
 	vmmc-supply = <&reg_usdhc2_vmmc>;
-	cd-gpios = <&lsio_gpio4 22 GPIO_ACTIVE_LOW>;
-	wp-gpios = <&lsio_gpio4 21 GPIO_ACTIVE_HIGH>;
+	no-1-8-v;
+	pm-ignore-notify;
+	sdhci,auto-cmd12;
+	enable-sdio-wakeup;
+	disable-wp;
+	cap-sdio-irq;
+	cap-sd-highspeed;
+	cap-mmc-highspeed;
+	wifi-host;
 	status = "okay";
 };

 	pinctrl_usdhc2_gpio: usdhc2gpiogrp {
 		fsl,pins = <
-			IMX8QXP_USDHC1_RESET_B_LSIO_GPIO4_IO19     0x00000021
-			IMX8QXP_USDHC1_WP_LSIO_GPIO4_IO21          0x00000021
-			IMX8QXP_USDHC1_CD_B_LSIO_GPIO4_IO22        0x00000021
+			IMX8QXP_USDHC1_RESET_B_LSIO_GPIO4_IO19     0x00000021	/* VSELECT */
+			IMX8QXP_USDHC1_VSELECT_LSIO_GPIO4_IO20     0x00000021	/* WIFI_EN */
+			IMX8QXP_USDHC1_WP_LSIO_GPIO4_IO21          0x00000020	/* WIFI_IRQ */
+			IMX8QXP_USDHC1_CD_B_LSIO_GPIO4_IO22        0x00000021	/* BT_EN */
 		>;
 	};

 	pinctrl_usdhc2: usdhc2grp {
 		fsl,pins = <
 			IMX8QXP_USDHC1_CLK_CONN_USDHC1_CLK			0x06000041
@@ -1462,7 +1480,6 @@
 			IMX8QXP_USDHC1_DATA1_CONN_USDHC1_DATA1			0x00000021
 			IMX8QXP_USDHC1_DATA2_CONN_USDHC1_DATA2			0x00000021
 			IMX8QXP_USDHC1_DATA3_CONN_USDHC1_DATA3			0x00000021
-			IMX8QXP_USDHC1_VSELECT_CONN_USDHC1_VSELECT		0x00000021
 		>;
 	};
```

需要注意的是DTS中设备`usdhc2`的属性，有一些常见属性会造成`rescan`不能成功，此时需要研究源码。

```config
non-removable   # only scan once（常常导致bcmdhd驱动回调rescan时失效的问题）
disable-wp      # 失能写保护
cd-inverted     # 插入检测电平
wifi-host       # 通常是需要的，如SDK没有实现该属性需要自行添加
```

如上修改之后没发现还是不能实现检测到`WiFi`模块，如果`SDIO`成功`rescan`后，会提示如下日志：

```dmesg
[   11.578432] mmc1: mmc_rescan_try_freq: trying to init card at 400000 Hz
[   11.620858] mmc1: queuing unknown CIS tuple 0x80 (2 bytes)
[   11.628297] mmc1: queuing unknown CIS tuple 0x80 (3 bytes)
[   11.635824] mmc1: queuing unknown CIS tuple 0x80 (3 bytes)
[   11.644650] mmc1: queuing unknown CIS tuple 0x80 (7 bytes)
[   11.763149] mmc1: new ultra high speed SDR104 SDIO card at address 0001
```

否则执行如下命令后是不能显示`SDIO`设备的：

```sh
mek_8q:/ # cat /sys/bus/sdio/devices/mmc1\:0001\:1/device
0xa9bf
```

通常的`rescan`逻辑如下：

```text
INIT_DELAYED_WORK(&host->detect, mmc_rescan);-------\
                                                    |
    wifi_card_detect                                |
    |-> ON --> mmc_detect_change                    |
    |       _mmc_detect_change                      |
    |           mmc_schedule_delayed_work           |
    |               queue_delayed_work              |
    |                   queue_delayed_work_on       |
    |                       mmc_rescan      <-------/
    |                           mmc_rescan_try_freq
    |                               mmc_power_up
    |                               mmc_hw_reset_for_init
    |                               sdio_reset
    |                               mmc_go_idle
    |                               mmc_send_if_cond
    |                               mmc_attach_sdio
    |                                   mmc_send_io_op_cond
    |                                   mmc_attach_bus
    |                                   mmc_select_voltage
    |                                   mmc_sdio_init_card
    |                                   sdio_init_func
    |                                   mmc_release_host
    |                                   mmc_add_card
    |                                   sdio_add_func
    |                                   mmc_claim_host
    |                               mmc_attach_sd
    |                               mmc_attach_mmc
    |
    `-> OFF -> mmc_sdio_force_remove
            mmc_sdio_remove
            mmc_claim_host
            mmc_detach_bus
            mmc_power_off
            mmc_release_host
```

参考资料：
[imx8qm wifi sdio调试](https://blog.csdn.net/u011784994/article/details/102476430)

### 2. 驱动添加

实现基本的MMC驱动的修改后，就可以开始添加WiFi驱动了。首先找供应商技术支持要WiFi驱动程序，然后按照供应商提供的说明文档尝试添加驱动程序到内核中去。

将压缩包中的 `bcmdhd_1.141.tar.gz` 解压后放到 `<kernel-dir>/drivers/net/wireless` 目录下

```bash
cp -fr bcmdhd <kernel-dir>/drivers/net/wireless/
```

添加bcmdhd目录到Kconfig中：将下面一行添加到 `<kernel-
dir>/drivers/net/wireless/Kconfig`，并且删除Broadcom的其他Kconfig(如果需要)

```Kconfig
source "drivers/net/wireless/bcmdhd/Kconfig"
```

添加bcmdhd目录到Makefile中：将下面一行添加到 `<kernel-
dir>/drivers/net/wireless/Makefile`

```Makfile
obj-$(CONFIG_BCMDHD) += bcmdhd/
```

修改bcmdhd目录下的Makefile，将其修改为适用于 Kernel 5.x 版本的样式

```diff
--- a/android_build/vendor/nxp-opensource/kernel_imx/drivers/net/wireless/bcmdhd/Makefile
+++ b/android_build/vendor/nxp-opensource/kernel_imx/drivers/net/wireless/bcmdhd/Makefile
@@ -13,7 +13,7 @@

-DHDCFLAGS += -DWL_CFG80211
+ccflags-y += -DWL_CFG80211

... ...

 ifeq ($(FW_ALIVE), 1)
-  DHDCFLAGS += -DLOAD_DHD_WITH_FW_ALIVE
+  ccflags-y += -DLOAD_DHD_WITH_FW_ALIVE
   DHDOFILES += dhd_chip_info.o
 endif
```

以前内核编译器是 GCC，目前的 iMX8 系统的默认编译器是 CLANG，所以会有这样的差异。

参照说明文档修改DTS文件，添加相应的节点

```diff
--- a/android_build/vendor/nxp-opensource/kernel_imx/arch/arm64/boot/dts/freescale/imx8x-mek.dtsi
+++ b/android_build/vendor/nxp-opensource/kernel_imx/arch/arm64/boot/dts/freescale/imx8x-mek.dtsi
@@ -9,12 +9,23 @@
 		stdout-path = &lpuart0;
 	};

-	brcmfmac: brcmfmac {
-		compatible = "cypress,brcmfmac";
-		pinctrl-names = "init", "idle", "default";
-		pinctrl-0 = <&pinctrl_wifi_init>;
-		pinctrl-1 = <&pinctrl_wifi_init>;
-		pinctrl-2 = <&pinctrl_wifi>;
+	wlreg_on: fixedregulator@13 {
+		compatible = "regulator-fixed";
+		regulator-name = "wlreg_on";
+		regulator-min-microvolt = <3300000>;
+		regulator-max-microvolt = <3300000>;
+		gpio = <&lsio_gpio4 20 GPIO_ACTIVE_HIGH>;   /* wifi en */
+		startup-delay-us = <600000>;
+		enable-active-high;
+	};
+
+	bcmdhd_wlan_0: bcmdhd_wlan@0 {
+		compatible = "android,bcmdhd_wlan";
+		pinctrl-names = "default";
+		pinctrl-0 = <&pinctrl_wifi>;
+		gpios = <&lsio_gpio4 21 GPIO_ACTIVE_LOW>;  /* wifi host wake IRQ */
+		wlreg_on-supply = <&wlreg_on>;
+		status = "okay";
 	};
```

执行Make mnenuconfig选择如下：

```diff
--- a/android_build/vendor/nxp-opensource/kernel_imx/arch/arm64/configs/imx_v8_android_defconfig
+++ b/android_build/vendor/nxp-opensource/kernel_imx/arch/arm64/configs/imx_v8_android_defconfig
@@ -421,8 +421,10 @@ CONFIG_USB_NET_SMSC75XX=m
 CONFIG_USB_NET_SMSC95XX=m
 CONFIG_USB_NET_PLUSB=m
 CONFIG_USB_NET_MCS7830=m
-CONFIG_BRCMFMAC=m
-CONFIG_BRCMFMAC_PCIE=y
+# CONFIG_WLAN_VENDOR_BROADCOM is not set
+CONFIG_BCMDHD=m
+CONFIG_BCMDHD_SDIO=y
+CONFIG_BCMDHD_NVRAM_PATH="/system/vendor/etc/wifi/bcmdhd.cal"
 CONFIG_HOSTAP=y
 CONFIG_WL18XX=m
 CONFIG_WLCORE_SDIO=m
```

至此，可以开始编译内核了，结果提示bcmdhd内的相关源码报错，经过分析发现，相关时间戳获取函数在当前 Kernel 5.x 下已经废弃不可用，遂修改相关代码，使用 Kernel 5.x 的时间戳获取 API 函数：

```diff
 	signal = notif_bss_info->rssi * 100;
 	if (!mgmt->u.probe_resp.timestamp) {
-#if (LINUX_VERSION_CODE >= KERNEL_VERSION(2, 6, 39))
+#if(LINUX_VERSION_CODE >= KERNEL_VERSION(5, 0, 0))
+	#ifndef CONFIG_ARCH_HAS_SYSCALL_WRAPPER
+		struct timeval tv;
+		sys_gettimeofday(&tv, NULL);
+		mgmt->u.probe_resp.timestamp = ((u64)tv.tv_sec*1000000)
+				+ tv.tv_usec;
+	#else
+		struct timespec ts;
+		if (!ktime_to_timespec_cond(ktime_get_boottime(), &ts))
+		{
+			ts.tv_sec = 0;
+			ts.tv_nsec = 0;
+		}
+		mgmt->u.probe_resp.timestamp = ((u64)ts.tv_sec*1000000)
+				+ ts.tv_nsec / 1000;
+	#endif
+#elif (LINUX_VERSION_CODE >= KERNEL_VERSION(2, 6, 39))
 		struct timespec ts;
 		get_monotonic_boottime(&ts);
 		mgmt->u.probe_resp.timestamp = ((u64)ts.tv_sec*1000000)
```

再次执行编译成功，但是手动执行加载驱动后报 Kernel panic 错误：

```text
[   10.935447] dhd_module_init in
[   10.940308] Power-up adapter 'DHD generic adapter'
[   10.945277] wifi_platform_bus_enumerate device present 1
[   11.008490] EXT4-fs (mmcblk0p9): 1 orphan inode deleted
[   11.013749] EXT4-fs (mmcblk0p9): recovery complete
[   11.024810] EXT4-fs (mmcblk0p9): mounted filesystem with ordered data mode. Opts: errors=remount-ro,nomblk_io_submit
[   11.578432] mmc1: mmc_rescan_try_freq: trying to init card at 400000 Hz
[   11.620858] mmc1: queuing unknown CIS tuple 0x80 (2 bytes)
[   11.628297] mmc1: queuing unknown CIS tuple 0x80 (3 bytes)
[   11.635824] mmc1: queuing unknown CIS tuple 0x80 (3 bytes)
[   11.644650] mmc1: queuing unknown CIS tuple 0x80 (7 bytes)
[   11.763149] mmc1: new ultra high speed SDR104 SDIO card at address 0001
[   11.781643] panel-raydium-rm67191 56228000.dsi_host.0: Failed to get reset gpio (-517)
[   11.791615] imx-cs42888 sound-cs42888: failed to find codec platform device
[   11.801831] imx-wm8960 sound-wm8960: failed to find codec platform device
[   11.809229] F1 signature read @0x18000000=0x15264345
[   11.813900] panel-raydium-rm67191 56248000.dsi_host.0: Failed to get reset gpio (-517)
[   11.814096] [drm] Supports vblank timestamp caching Rev 2 (21.10.2013).
[   11.814179] [drm] No driver support for vblank timestamp query.
[   11.814270] imx-drm display-subsystem: bound imx-drm-dpu-bliteng.2 (ops dpu_bliteng_ops)
[   11.814477] imx-drm display-subsystem: bound imx-dpu-crtc.0 (ops dpu_crtc_ops)
[   11.814639] imx-drm display-subsystem: bound imx-dpu-crtc.1 (ops dpu_crtc_ops)
[   11.814696] imx-drm display-subsystem: failed to bind 56228000.dsi_host (ops nwl_dsi_component_ops): -517
[   11.814888] imx-drm display-subsystem: master bind failed: -517
[   11.819633] panel-raydium-rm67191 56228000.dsi_host.0: Failed to get reset gpio (-517)
[   11.820437] imx-cs42888 sound-cs42888: failed to find codec platform device
[   11.898869] F1 signature OK, socitype:0x1 chip:0x4345 rev:0x6 pkg:0x2
[   11.907372] DHD: dongle ram size is set to 819200(orig 819200) at 0x198000
[   11.914829] firmware path not found
[   11.918448] CFG80211-ERROR) wl_setup_wiphy :
[   11.918451] Registering Vendor80211
[   11.922954] ------------[ cut here ]------------
[   11.930981] WARNING: CPU: 3 PID: 286 at /sdk/android_build/vendor/nxp-opensource/kernel_imx/net/wireless/core.c:867 wiphy_register+0x70c/0x7f8
[   11.930986] Modules linked in: cywdhd(+)
[   11.947692] CPU: 3 PID: 286 Comm: insmod Not tainted 5.4.24 #57
[   11.947696] Hardware name: Freescale i.MX8QXP MEK (DT)
[   11.947702] pstate: 20400005 (nzCv daif +PAN -UAO)
[   11.947710] pc : wiphy_register+0x70c/0x7f8
[   11.947808] lr : wl_cfg80211_attach+0x278/0xd28 [cywdhd]
[   11.947823] sp : ffff80002437b350
[   11.958876] x29: ffff80002437b3d0 x28: 00000000ffffffea
[   11.958882] x27: ffff80001193b000 x26: ffff8000093fc000
[   11.958888] x25: ffff8000093fc000 x24: ffff800009402000
[   11.958894] x23: ffff8000093fc000 x22: 000000000000070e
[   11.958903] x21: 0000000000000000 x20: ffff00082d5c0000
[   11.967877] x19: ffff00082d5c0300 x18: 000000000000070e
[   11.967883] x17: 0000000000000014 x16: 000000000000000e
[   11.967888] x15: 000000000000000e x14: 0000000000000001
[   11.967893] x13: 0000000000000000 x12: 0000000000000000
[   11.967899] x11: 0000000000000000 x10: 0000000000000030
[   11.967904] x9 : ffff8000093db570 x8 : 0000000000000012
[   11.967910] x7 : 735f6c772029524f x6 : ffff8000120ba909
[   11.967916] x5 : 0000000000000000 x4 : 000000000000000c
[   11.967921] x3 : 0000000000000000 x2 : 0000000000000005
[   11.967935] x1 : 0000000000000001 x0 : 0000000000000002
[   11.976572] Call trace:
[   11.976586]  wiphy_register+0x70c/0x7f8
[   11.976683]  wl_cfg80211_attach+0x278/0xd28 [cywdhd]
[   11.976765]  dhd_attach+0x368/0x76c [cywdhd]
[   11.987399]  dhdsdio_probe+0x1f4/0x548 [cywdhd]
[   11.987476]  bcmsdh_probe+0x104/0x178 [cywdhd]
[   11.998095]  bcmsdh_sdmmc_probe+0xc4/0x118 [cywdhd]
[   11.998114]  sdio_bus_probe+0x130/0x1e8
[   12.008732]  really_probe+0x254/0x540
[   12.019345]  driver_probe_device+0x60/0xf8
[   12.029963]  device_driver_attach+0x68/0xa4
[   12.040577]  __driver_attach+0xc0/0x140
[   12.040582]  bus_for_each_dev+0x78/0xc0
[   12.040588]  driver_attach+0x20/0x28
[   12.040593]  bus_add_driver+0xf8/0x1d8
[   12.040599]  driver_register+0x74/0x108
[   12.040606]  sdio_register_driver+0x24/0x2c
[   12.040690]  bcmsdh_register_client_driver+0x14/0x1c [cywdhd]
[   12.040762]  bcmsdh_register+0x24/0x2c [cywdhd]
[   12.051393]  dhd_bus_register+0x20/0x40 [cywdhd]
[   12.051471]  dhd_wifi_platform_load+0x334/0x53c [cywdhd]
[   12.059217]  wifi_plat_dev_drv_probe+0x108/0x170 [cywdhd]
[   12.067944]  platform_drv_probe+0x8c/0xb4
[   12.076734]  really_probe+0x254/0x540
[   12.086047]  driver_probe_device+0x60/0xf8
[   12.086053]  device_driver_attach+0x68/0xa4
[   12.086058]  __driver_attach+0xc0/0x140
[   12.086064]  bus_for_each_dev+0x78/0xc0
[   12.086071]  driver_attach+0x20/0x28
[   12.093560]  bus_add_driver+0xf8/0x1d8
[   12.093566]  driver_register+0x74/0x108
[   12.093571]  __platform_driver_register+0x40/0x48
[   12.093647]  dhd_wifi_platform_register_drv+0x1cc/0x274 [cywdhd]
[   12.093729]  init_module+0xb0/0x1000 [cywdhd]
[   12.101940]  do_one_initcall+0x138/0x2c8
[   12.101949]  do_init_module+0x58/0x218
[   12.101955]  load_module+0x30ec/0x3890
[   12.101961]  __arm64_sys_finit_module+0xb4/0xe4
[   12.101971]  el0_svc_common+0x98/0x150
[   12.101984]  el0_svc_handler+0x68/0x80
[   12.109648]  el0_svc+0x8/0xc
[   12.109653] ---[ end trace 01d8d681bc929130 ]---
[   12.109733] CFG80211-ERROR) wl_setup_wiphy :
[   12.109737] Couldn not register wiphy device (-22)
[   12.117088] wl_cfg80211_attach failed
[   12.230135] Unable to handle kernel access to user memory outside uaccess routines at virtual address 00000000000005d0
[   12.236198] Mem abort info:
[   12.244673]   ESR = 0x96000004
[   12.244682]   EC = 0x25: DABT (current EL), IL = 32 bits
[   12.244691]   SET = 0, FnV = 0
[   12.258259]   EA = 0, S1PTW = 0
[   12.266643] Data abort info:
[   12.272841]   ISV = 0, ISS = 0x00000004
[   12.272847]   CM = 0, WnR = 0
[   12.279616] user pgtable: 4k pages, 48-bit VAs, pgdp=00000008b5afa000
[   12.289089] [00000000000005d0] pgd=0000000000000000
[   12.294029] Internal error: Oops: 96000004 [#1] PREEMPT SMP
[   12.294036] mmc0: starting CQE transfer for tag 14 blkaddr 25218704
[   12.294577] mmc0: sdhci: IRQ status 0x00004000
[   12.294586] mmc0: CQE transfer done tag 13
[   12.294590] mmc0:     131072 bytes transferred: 0
[   12.299613] Modules linked in: cywdhd(+)
[   12.299629] CPU: 1 PID: 286 Comm: insmod Tainted: G        W         5.4.24 #57
[   12.299632] Hardware name: Freescale i.MX8QXP MEK (DT)
[   12.299637] pstate: 60400005 (nZCv daif +PAN -UAO)
[   12.299651] pc : mutex_lock+0xc/0x38
[   12.299752] lr : wl_cfg80211_down+0x64/0xad4 [cywdhd]
[   12.299760] sp : ffff80002437b340
[   12.306079] mmc0:     blksz 512 blocks 256 flags 00000200 tsac 100 ms nsac 0
[   12.310476] x29: ffff80002437b3c0 x28: 00000000000005d0
[   12.310482] x27: 0000000000000001 x26: 0000000000011618
[   12.310487] x25: 00000000000114be x24: ffff8000093fc000
[   12.310493] x23: ffff800009403000 x22: 0000000000000001
[   12.310502] x21: 000000000000534c x20: 0000000000000000
[   12.314669] mmc0: starting CQE transfer for tag 15 blkaddr 25218960
[   12.315189] mmc0: sdhci: IRQ status 0x00004000
[   12.315198] mmc0: CQE transfer done tag 14
[   12.315202] mmc0:     131072 bytes transferred: 0
[   12.319303] x19: ffff00082d560000 x18: 0000000000000040
[   12.319309] x17: 0000000000000041 x16: 0000000000000001
[   12.319314] x15: 0000000000000010 x14: 0000000000000010
[   12.319320] x13: 0000000000000000 x12: ffff800011bc1060
[   12.319325] x11: 0000000000000000 x10: 0000000000000000
[   12.319331] x9 : ffff00083a41e740 x8 : 0000000000000000
[   12.319341] x7 : 65725f6f69647320 x6 : ffff8000120ba907
[   12.323313] mmc0:     blksz 512 blocks 120 flags 00000200 tsac 100 ms nsac 0
[   12.330578] x5 : 0000000000000000 x4 : 0000000000000004
[   12.330583] x3 : 000000000000000a x2 : ffff00083f9abf50
[   12.330589] x1 : 0000000000000000 x0 : 00000000000005d0
[   12.330595] Call trace:
[   12.330613]  mutex_lock+0xc/0x38
[   12.335823] mmc0: starting CQE transfer for tag 12 blkaddr 25219088
[   12.336175] mmc0: sdhci: IRQ status 0x00004000
[   12.336184] mmc0: CQE transfer done tag 15
[   12.336188] mmc0:     61440 bytes transferred: 0
[   12.340615]  dhd_detach+0xac/0x540 [cywdhd]
[   12.340689]  dhd_attach+0x320/0x76c [cywdhd]
[   12.344213] mmc0:     blksz 512 blocks 384 flags 00000200 tsac 100 ms nsac 0
[   12.349313]  dhdsdio_probe+0x1f4/0x548 [cywdhd]
[   12.349386]  bcmsdh_probe+0x104/0x178 [cywdhd]
[   12.352683] mmc0: starting CQE transfer for tag 13 blkaddr 25481224
[   12.354005] mmc0: sdhci: IRQ status 0x00004000
[   12.354014] mmc0: CQE transfer done tag 12
[   12.354017] mmc0:     196608 bytes transferred: 0
[   12.359745]  bcmsdh_sdmmc_probe+0xc4/0x118 [cywdhd]
[   12.359758]  sdio_bus_probe+0x130/0x1e8
[   12.365102] mmc0:     blksz 512 blocks 8 flags 00000200 tsac 100 ms nsac 0
[   12.370373]  really_probe+0x254/0x540
[   12.370380]  driver_probe_device+0x60/0xf8
[   12.370386]  device_driver_attach+0x68/0xa4
[   12.370395]  __driver_attach+0xc0/0x140
[   12.370405]  bus_for_each_dev+0x78/0xc0
[   12.375918] mmc0: sdhci: IRQ status 0x00004000
[   12.381023]  driver_attach+0x20/0x28
[   12.386331] mmc0: CQE transfer done tag 13
[   12.392594]  bus_add_driver+0xf8/0x1d8
[   12.397031] mmc0:     4096 bytes transferred: 0
[   12.401126]  driver_register+0x74/0x108
[   12.407603] mmc0: starting CQE transfer for tag 14 blkaddr 25478160
[   12.411135]  sdio_register_driver+0x24/0x2c
[   12.411226]  bcmsdh_register_client_driver+0x14/0x1c [cywdhd]
[   12.411300]  bcmsdh_register+0x24/0x2c [cywdhd]
[   12.416576] mmc0:     blksz 512 blocks 128 flags 00000200 tsac 100 ms nsac 0
[   12.421922]  dhd_bus_register+0x20/0x40 [cywdhd]
[   12.421997]  dhd_wifi_platform_load+0x334/0x53c [cywdhd]
[   12.428858] mmc0: sdhci: IRQ status 0x00004000
[   12.432625]  wifi_plat_dev_drv_probe+0x108/0x170 [cywdhd]
[   12.437867] mmc0: CQE transfer done tag 14
[   12.443174]  platform_drv_probe+0x8c/0xb4
[   12.450216] mmc0:     65536 bytes transferred: 0
[   12.455527]  really_probe+0x254/0x540
[   12.461272] mmc0: starting CQE transfer for tag 12 blkaddr 25478288
[   12.466142]  driver_probe_device+0x60/0xf8
[   12.466148]  device_driver_attach+0x68/0xa4
[   12.466154]  __driver_attach+0xc0/0x140
[   12.466159]  bus_for_each_dev+0x78/0xc0
[   12.466165]  driver_attach+0x20/0x28
[   12.466170]  bus_add_driver+0xf8/0x1d8
[   12.466177]  driver_register+0x74/0x108
[   12.468619] mmc0:     blksz 512 blocks 256 flags 00000200 tsac 100 ms nsac 0
[   12.471839]  __platform_driver_register+0x40/0x48
[   12.471916]  dhd_wifi_platform_register_drv+0x1cc/0x274 [cywdhd]
[   12.471992]  init_module+0xb0/0x1000 [cywdhd]
[   12.478260] mmc0: starting CQE transfer for tag 13 blkaddr 25478544
[   12.479976] mmc0: sdhci: IRQ status 0x00004000
[   12.479985] mmc0: CQE transfer done tag 12
[   12.479988] mmc0:     131072 bytes transferred: 0
[   12.482645]  do_one_initcall+0x138/0x2c8
[   12.482655]  do_init_module+0x58/0x218
[   12.482661]  load_module+0x30ec/0x3890
[   12.482667]  __arm64_sys_finit_module+0xb4/0xe4
[   12.482675]  el0_svc_common+0x98/0x150
[   12.482684]  el0_svc_handler+0x68/0x80
[   12.482690]  el0_svc+0x8/0xc
[   12.482704] Code: d65f03c0 aa1f03e8 d5384109 f9800011 (c85ffc0b)
[   12.486834] mmc0:     blksz 512 blocks 256 flags 00000200 tsac 100 ms nsac 0
[   12.491419] ---[ end trace 01d8d681bc929131 ]---
[   12.522991] Kernel panic - not syncing: Fatal exception
[   12.525044] mmc0: starting CQE transfer for tag 14 blkaddr 25478800
[   12.525548] mmc0: sdhci: IRQ status 0x00004000
[   12.525557] mmc0: CQE transfer done tag 13
[   12.525561] mmc0:     131072 bytes transferred: 0
[   12.531233] SMP: stopping secondary CPUs
[   12.531252] Kernel Offset: disabled
[   12.531258] CPU features: 0x00000002,20002008
[   12.531261] Memory Limit: none
[   12.857851] Rebooting in 5 seconds..
```

根据错误信息定位到相应的代码中去，并屏蔽引发该错误的代码：

```diff
--- a/android_build/vendor/nxp-opensource/kernel_imx/net/wireless/core.c
+++ b/android_build/vendor/nxp-opensource/kernel_imx/net/wireless/core.c
@@ -857,7 +857,7 @@ int wiphy_register(struct wiphy *wiphy)
 		WARN_ON(1);
 		return -EINVAL;
 	}
-
+#if 0
 	for (i = 0; i < rdev->wiphy.n_vendor_commands; i++) {
 		/*
 		 * Validate we have a policy (can be explicitly set to
@@ -870,7 +870,7 @@ int wiphy_register(struct wiphy *wiphy)
 			    !rdev->wiphy.vendor_commands[i].dumpit))
 			return -EINVAL;
 	}
-
+#endif
```

再重新加载后，就没有错误了。将当前驱动`cywdhd.ko`设置开机默认加载：

```diff
--- a/android_build/device/fsl/imx8q/mek_8q/early.init.cfg
+++ b/android_build/device/fsl/imx8q/mek_8q/early.init.cfg
+insmod vendor/lib/modules/cywdhd.ko
```

### 3. 测试驱动

驱动加载成功后，串口日志会显示驱动成功注册了：

```dmesg
[   15.006005] Register interface [wlan0]  MAC: 82:a3:10:00:f7:fb
```

此时执行`ifconfig -a`查看网卡状态，就能检测到网卡`wlan0`的存在。

```sh
mek_8q:/ # ifconfig -a
... ...
wlan0     Link encap:Ethernet  HWaddr 82:a3:10:00:f7:fb  Driver bcmsdh_sdmmc
          UP BROADCAST MULTICAST  MTU:1500  Metric:1
          RX packets:0 errors:0 dropped:0 overruns:0 frame:0
          TX packets:5 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:1000
          RX bytes:0 TX bytes:426
```

手动开启 `wpa_supplicant` 服务：

```
mek_8q:/ # /vendor/bin/hw/wpa_supplicant -iwlan0 -Dnl80211 -c/vendor/etc/wifi/wpa_supplicant.conf
```

通过`ps`命令查看wpa服务是否能够正常执行：

```
mek_8q:/ # ps -A | grep wpa_supplicant
```

通过`logcat`命令查看wpa服务是否能够正常执行：

```
mek_8q:/ # logcat | grep wpa
```

遇到过一次日志中显示不能操作`rfkill`引起的不能打开`wlan0`网卡的现象，经过排查，发现内核中`CONFIG_BCMDHD`的配置需要修改为`m`。

如有结果则表明`wpa_supplicant`服务正常运行，此时需要执行`wpa_cli`客户端来实现无UI界面情况下的`WiFi`连接：

```
mek_8q:/ # wpa_cli
wpa_cli v2.8-devel-10
Copyright (c) 2004-2019, Jouni Malinen <j@w1.fi> and contributors

This software may be distributed under the terms of the BSD license.
See README for more details.


Using interface 'wlan0'

Interactive mode

> add network
1
> set_network 1 ssid "xxxx"
OK
> set_network 1 psk "yyyyyyyyy"
OK
> select_network 1
OK
> enable_network 1
OK
> q
```

如果连接成功，就能在`select_network`这一步看到网络连接成功的提示`CTRL-EVENT-CONNECTED`事件：

```
<3>CTRL-EVENT-STATE-CHANGE id=0 state=3 BSSID=00:00:00:00:00:00 SSID=XXXXX
<3>CTRL-EVENT-STATE-CHANGE id=0 state=0 BSSID=00:00:00:00:00:00 SSID=XXXXX
<3>CTRL-EVENT-SCAN-FAILED ret=-11 retry=1
<3>CTRL-EVENT-STATE-CHANGE id=0 state=3 BSSID=00:00:00:00:00:00 SSID=XXXXX
<3>CTRL-EVENT-SCAN-STARTED
<3>CTRL-EVENT-SCAN-RESULTS
<3>WPS-AP-AVAILABLE
<3>Trying to associate with SSID 'XXXXX'
<3>CTRL-EVENT-STATE-CHANGE id=0 state=5 BSSID=00:00:00:00:00:00 SSID=XXXXX
<3>CTRL-EVENT-STATE-CHANGE id=0 state=6 BSSID=00:00:00:00:00:00 SSID=XXXXX
<3>Associated with 74:0a:e1:61:ae:fc
<3>CTRL-EVENT-STATE-CHANGE id=0 state=7 BSSID=74:0a:e1:61:ae:fc SSID=XXXXX
<3>WPA: RX message 1 of 4-Way Handshake from 74:0a:e1:61:ae:fc (ver=2)
<3>WPA: Sending EAPOL-Key 2/4
<3>CTRL-EVENT-SUBNET-STATUS-UPDATE status=0
<3>WPA: RX message 3 of 4-Way Handshake from 74:0a:e1:61:ae:fc (ver=2)
<3>WPA: Sending EAPOL-Key 4/4
<3>CTRL-EVENT-STATE-CHANGE id=0 state=8 BSSID=74:0a:e1:61:ae:fc SSID=XXXXX
<3>WPA: Key negotiation completed with 74:0a:e1:61:ae:fc [PTK=CCMP GTK=CCMP]
<3>CTRL-EVENT-CONNECTED - Connection to 74:0a:e1:61:ae:fc completed [id=0 id_str
=]
<3>CTRL-EVENT-STATE-CHANGE id=0 state=9 BSSID=74:0a:e1:61:ae:fc SSID=XXXXX
<3>CTRL-EVENT-DISCONNECTED bssid=74:0a:e1:61:ae:fc reason=3 locally_generated=1
<3>CTRL-EVENT-STATE-CHANGE id=0 state=0 BSSID=74:0a:e1:61:ae:fc SSID=XXXXX
<3>CTRL-EVENT-REGDOM-CHANGE init=CORE type=WORLD
```

如果成功，可以执行`ifconfig`和`ping`命令来查看网络是否正常连接到`Internet`

```sh
mek_8q:/ # ifconfig
... ...

wlan0     Link encap:Ethernet  HWaddr 82:a3:10:00:f7:fb  Driver bcmsdh_sdmmc
          inet addr:192.168.3.100  Bcast:192.168.3.255  Mask:255.255.255.0
          UP BROADCAST MULTICAST  MTU:1500  Metric:1
          RX packets:4 errors:0 dropped:0 overruns:0 frame:0
          TX packets:7 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:1000
          RX bytes:346 TX bytes:674
```

如果发现`wlan0`网卡并没有分配到可用的IP地址，或者存在IP地址但是`ping`操作没有反应，那么有可能是其他原因引起的问题，比如`DNS`或`DHCP`等问题，此时可以向供应商寻求技术支持。

```bash
mek_8q:/ # ping 8.8.8.8
connect: Network is unreachable
```

```bash
mek_8q:/ # ping 8.8.8.8
PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
64 bytes from 8.8.8.8: icmp_seq=1 ttl=109 time=92.0 ms
64 bytes from 8.8.8.8: icmp_seq=2 ttl=109 time=98.8 ms
64 bytes from 8.8.8.8: icmp_seq=3 ttl=109 time=199 ms
```

### 4. 修改 service

将相关固件和配置文件添加到系统中去：

```diff
--- a/android_build/device/fsl/imx8q/mek_8q/SharedBoardConfig.mk
+++ b/android_build/device/fsl/imx8q/mek_8q/SharedBoardConfig.mk

+# Goodcom wifi&bt driver module
 BOARD_VENDOR_KERNEL_MODULES += \
-    $(KERNEL_OUT)/drivers/net/wireless/marvell/mrvl8997/wlan_src/mlan.ko \
-    $(KERNEL_OUT)/drivers/net/wireless/marvell/mrvl8997/wlan_src/pcie8xxx.ko
+    $(KERNEL_OUT)/drivers/net/wireless/bcmdhd/cywdhd.ko
+
+PRODUCT_COPY_FILES += \
+    hardware/goodcom/firmware/BCM43455/fw_bcm43455c0_ag.bin:$(TARGET_COPY_OUT_VENDOR)/firmware/fw_bcmdhd.bin \
+    hardware/goodcom/firmware/BCM43455/nvram_bcm43455.txt:$(TARGET_COPY_OUT_VENDOR)/etc/wifi/bcmdhd.cal \
+    hardware/goodcom/firmware/BCM43455/p2p_supplicant.conf:$(TARGET_COPY_OUT_VENDOR)/etc/wifi/p2p_supplicant.conf
```

参照参考手册，修改board 下面的 init.rc 文件：

```diff
--- a/android_build/device/fsl/imx8q/mek_8q/init.rc
+++ b/android_build/device/fsl/imx8q/mek_8q/init.rc

-    setprop wifi.direct.interface p2p0
-    setprop wifi.concurrent.interface wlan1
+    setprop wifi.direct.interface p2p-dev-wlan0
+    setprop wifi.concurrent.interface wlan0

 service wpa_supplicant /vendor/bin/hw/wpa_supplicant \
+    -iwlan0 -Dnl80211 -c/vendor/etc/wifi/wpa_supplicant.conf \
+    -m/vendor/etc/wifi/p2p_supplicant.conf \
     -O/data/vendor/wifi/wpa/sockets -puse_p2p_group_interface=1 \
     -g@android:wpa_wlan0
     interface android.hardware.wifi.supplicant@1.0::ISupplicant default
```

该服务可以实现系统在默认打开`WiFi`的时候，开机默认启动`wpa_supplicant`服务。

在无UI界面的情况下，执行`svc`命令可以起到在UI界面打开/关闭`WiFi`同样的效果：

```bash
mek_8q:/ # svc wifi enable
mek_8q:/ # svc wifi disable
```

如果发现开机不能启动`wpa_supplicant`服务，可以同如上方法，查找问题原因，常见的问题有：`init.rc`中参数错误、`wpa_supplicant`无法打开某些文件节点。

## 三. Wifi 功能测试

### 1. Invalid key mgmt——无法连接到有密码保护的WiFi热点

当尝试用`wpa_cli`或者UI界面连接到某个指定`WiFi`的时候就能在串口日志中看到如下的密码错误、鉴权失败的信息：

```dmesg
[249170.757895] CFG80211-ERROR) wl_set_key_mgmt :
[249170.757899] mfp set failed ret:-23
[249170.766117] CFG80211-ERROR) wl_cfg80211_connect :
[249170.766121] Invalid key mgmt
[249170.826383] init: Untracked pid 7847 exited with status 0
```

![WPA客户端连接WiFi失败][wpa_cli_connect_wifi_error]

通过供应商技术支持，修改默认的`wpa_supplicant.conf`文件解决该问题：

```diff
--- a/android_build/external/wpa_supplicant_8/wpa_supplicant/wpa_supplicant_template.conf
+++ b/android_build/external/wpa_supplicant_8/wpa_supplicant/wpa_supplicant_template.conf
@@ -1,7 +1,11 @@
 ##### wpa_supplicant configuration file template #####
 update_config=1
+ctrl_interface=/data/vendor/wifi/wpa/sockets
 eapol_version=1
 ap_scan=1
 fast_reauth=1
-pmf=1
-p2p_add_cli_chan=1
+driver_param=use_p2p_group_interface=1p2p_device=1
+device_name=BU-FMAC-DEV1
+device_type=10-0050F204-5
+config_methods=virtual_push_button physical_display keyboard
+interworking=1
```

### 2. 连接受限问题——Captive Potal Service

![WiFi连接受限][wifi_limited_connection]

显示如上现象时，`ping`百度等网络是可以`ping`通的，说明已连接到`Internet`网络，但是重启之后，之前记忆的网络却不能自动重连了。在寻求技术支持后尝试以下命令，发现问题解决：

```bash
adb shell settings delete global captive_portal_server
adb shell settings put global captive_portal_detection_enabled 0
adb shell settings put global captive_portal_https_url https://www.google.cn/generate_204
adb shell settings put global captive_portal_server http://www.g.cn
```

谷歌在Android5.0之后的版本加入了CaptivePotalLogin服务。本服务的功能是检查网络连接互联网情况，主要针对于Wi-Fi，不让Android设备自动连接那些不能联网的无线热点，白白耗电。
该服务的原理就是让接入无线热点后，测一下网站`connectivitycheck.gstatic.com`的联通情况。但对于不能访问谷歌服务器的地区，问题就来了：

1. 如果谷歌（谷歌服务）认为WiFi网络无法联网，就不会自动连接到该WiFi热点。而且如果设备有移动网络可用，就会自动切换到2G/3G/LTE。并且让WiFi网络的标志上面显示感叹号标志。
2. 出现感叹号的同时，该服务会一直试探服务器，直到联通为止。该过程会消耗流量和电量，甚至导致部分设备无法休眠。
3. 这个感叹号会使广大强迫症晚期患者无法接受。

确认是这个问题后参考相关资料，修改SDK如下：

默认的`defaults.xml`文件保存值：
```diff
--- a/android_build/frameworks/base/packages/SettingsProvider/res/values/defaults.xml
+++ b/android_build/frameworks/base/packages/SettingsProvider/res/values/defaults.xml
@@ -51,6 +51,10 @@
     <bool name="def_wifi_wakeup_enabled">true</bool>
     <bool name="def_networks_available_notification_on">true</bool>

+    <integer name="def_captive_portal_detection_enabled">0</integer>
+    <string name="def_captive_portal_https_url">https://www.google.cn/generate_204</string>
+    <string name="def_captive_portal_server">http://www.g.cn/</string>
+
     <bool name="def_backup_enabled">false</bool>
```

在相关文件中添加开机加载默认参数的操作：
```diff
--- a/android_build/frameworks/base/packages/SettingsProvider/src/com/android/providers/settings/DatabaseHelper.java
+++ b/android_build/frameworks/base/packages/SettingsProvider/src/com/android/providers/settings/DatabaseHelper.java
@@ -2606,6 +2606,16 @@ class DatabaseHelper extends SQLiteOpenHelper {
         private void loadGlobalSettings(SQLiteDatabase db) {

             loadIntegerSetting(stmt, Global.HEADS_UP_NOTIFICATIONS_ENABLED,
                     R.integer.def_heads_up_enabled);

+            loadIntegerSetting(stmt, Settings.Global.CAPTIVE_PORTAL_DETECTION_ENABLED,
+                    R.integer.def_captive_portal_detection_enabled);
+
+            loadStringSetting(stmt, Settings.Global.CAPTIVE_PORTAL_HTTPS_URL,
+                    R.string.def_captive_portal_https_url);
+
+            loadStringSetting(stmt, Settings.Global.CAPTIVE_PORTAL_SERVER,
+                    R.string.def_captive_portal_server);
+            android.util.Log.d("target", " CAPTIVE_PORTAL setted");
+
             loadSetting(stmt, Settings.Global.DEVICE_NAME, getDefaultDeviceName());
```

重新编译烧录后测试OK。

参考资料：
[Android系统开发之修改Captive Potal Service（消灭感叹号）](https://segmentfault.com/a/1190000006189911)

### 3. P2P——WiFi直连功能

由于手机互联等软件可能需要车机平台实现P2P功能，所以在功能上需要测试`P2P`直接连接功能。

可以借助由亿联提供的测试软件`wifidirect_example.apk`，用于测试车机与手机之间的`P2P`直连功能。

![P2P直连功能][p2p_wifi_direct_example]

测试方法：

1. 将车机与手机都安装测试软件`wifidirect_example.apk`，并选中所有请求权限
2. 将手机与车机共同连接到相同的`WiFi`热点之下
3. 点击`ADD LOCAL SERVICE`后选择`SCAN`即可扫描到该`WiFi`下的所有`P2P`设备
4. 搜索到设备后可以点击`CONNECT`进行连接，连接成功之后可以进行`TEST 100`测试

命令行查看`p2p`网卡是否成功创建：

```bash
mek_8q:/ # ifconfig
eth0      Link encap:Ethernet  HWaddr de:d8:9d:3a:ef:83  Driver fec
          UP BROADCAST MULTICAST  MTU:1500  Metric:1
          RX packets:0 errors:0 dropped:0 overruns:0 frame:0
          TX packets:79 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:1000
          RX bytes:0 TX bytes:9706

wlan0     Link encap:Ethernet  HWaddr 82:a3:10:00:f7:fb  Driver bcmsdh_sdmmc
          inet addr:192.168.3.48  Bcast:192.168.3.255  Mask:255.255.255.0
          inet6 addr: fe80::45ee:cb82:56a1:c93d/64 Scope: Link
          UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
          RX packets:1250 errors:0 dropped:0 overruns:0 frame:0
          TX packets:1750 errors:0 dropped:5 overruns:0 carrier:0
          collisions:0 txqueuelen:1000
          RX bytes:193505 TX bytes:161000

p2p-wlan0-0 Link encap:Ethernet  HWaddr 86:a3:10:00:77:fb  Driver bcmsdh_sdmmc
          inet6 addr: fe80::84a3:10ff:fe00:77fb/64 Scope: Link
          UP BROADCAST MULTICAST  MTU:1500  Metric:1
          RX packets:0 errors:0 dropped:0 overruns:0 frame:0
          TX packets:2 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:1000
          RX bytes:0 TX bytes:176

lo        Link encap:Local Loopback
          inet addr:127.0.0.1  Mask:255.0.0.0
          inet6 addr: ::1/128 Scope: Host
          UP LOOPBACK RUNNING  MTU:65536  Metric:1
          RX packets:7297 errors:0 dropped:0 overruns:0 frame:0
          TX packets:7297 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:1000
          RX bytes:4592900 TX bytes:4592900
```

![P2P测试结果][p2p_test_100_result]

## 四. BT 可执行文件获取与SDK适配

### 1. SDK适配

BT方面需要确认`rfkill`和串口，当前DTS里面的串口是不需要修改的，仅需要添加`rfkill`，默认使用系统中已经实现的`mxc_bt_rfkill`：

```diff
--- a/android_build/vendor/nxp-opensource/kernel_imx/arch/arm64/boot/dts/freescale/imx8x-mek.dtsi
+++ b/android_build/vendor/nxp-opensource/kernel_imx/arch/arm64/boot/dts/freescale/imx8x-mek.dtsi

+	bluetooth_0: bcmdhd_bt@0 {
+		compatible = "fsl,mxc_bt_rfkill";
+		bt-power-gpios = <&lsio_gpio4 22 GPIO_ACTIVE_LOW>;  /* bluetooth enable */
+		status = "okay";
+	};
```

但是`mxc_bt_rfkill`的驱动没有实现蓝牙电源的关闭操作，需要按照要求修改如下：

```diff
--- a/android_build/vendor/nxp-opensource/kernel_imx/drivers/bluetooth/mx8_bt_rfkill.c
+++ b/android_build/vendor/nxp-opensource/kernel_imx/drivers/bluetooth/mx8_bt_rfkill.c

+static int mxc_bt_rfkill_output(void *rfkdata, int is_push_high)
+{
+	struct mxc_bt_rfkill_data *data = rfkdata;
+	printk(KERN_INFO "mxc_bt_rfkill_output\n");
+	if (gpio_is_valid(data->bt_power_gpio)) {
+		if (is_push_high > 1)	is_push_high = 1;
+
+		gpio_set_value_cansleep(data->bt_power_gpio, is_push_high);
+		msleep(500);
+		return 0;
+	}
+	else	return -1;
+}

 static int mxc_bt_rfkill_power_change(void *rfkdata, int status)
 {
+#if 0
 	if (status)
 		mxc_bt_rfkill_reset(rfkdata);
 	return 0;
+#else
+	return mxc_bt_rfkill_output(rfkdata, status);
+#endif
 }
```

添加以上`rfkill`和串口后可以使用`echo`命令测试其功能，并用示波器检查是否正常：

```bash
mek_8q:/ # echo 0 > /sys/class/rfkill/rfkill0/state     # 拉低BT_EN引脚
mek_8q:/ # echo 1 > /sys/class/rfkill/rfkill0/state     # 拉高BT_EN引脚
```

某些`Linux`系统可能需要`echo`字符串给设备节点：

```bash
mek_8q:/ # echo "0" > /sys/class/rfkill/rfkill0/state   # 拉低BT_EN引脚
mek_8q:/ # echo "1" > /sys/class/rfkill/rfkill0/state   # 拉高BT_EN引脚
```

同理，也可以用示波器检查串口是否有波形，以此判断串口是否正常：

```bash
mek_8q:/ # echo "AAAAAAAAAAAAAAABBBBBB" > /dev/ttyLP1   # 向串口写入数据
```

### 2. BT 可执行文件获取
通常，供应商需要客户提供相关AOSP上的一些库文件和头文件用于供应商方面编译蓝牙服务的可执行文件，通常包含如下文件：

![供应商需要的头文件][supplier_needed_header_files]

![供应商需要的库文件][supplier_needed_library_files]

需要注意到`tinyalsa`的版本是否匹配，如果头文件不匹配的话，可能会造成蓝牙服务打开PCM设备失败的情况。

除此之外，还需要提供控制`BT_EN`的`rfkill`文件节点和蓝牙使用的串口文件节点，通常配置如下：

```text
UART:       /dev/ttyLP1
I2S:        /dev/snd/pcmC0D0x
RFKILL:     /sys/class/rfkill/rfkill0/state
BT_EN ON:   echo 1 > /sys/class/rfkill/rfkill0/state
BT_EN OFF:  echo 0 > /sys/class/rfkill/rfkill0/state
```

供应商方面会提供如下文件：

```text
gocsdk              # 蓝牙服务
libGbtsTask.so      # 依赖库文件
double.apk          # 蓝牙测试APP
```

其中`gocsdk`就是蓝牙服务的可执行文件。

### 3. 开启 BT 服务

将相关文件添加到系统中去：

```diff
--- a/android_build/device/fsl/imx8q/mek_8q/SharedBoardConfig.mk
+++ b/android_build/device/fsl/imx8q/mek_8q/SharedBoardConfig.mk

 PRODUCT_COPY_FILES += \
     hardware/goodcom/firmware/BCM43455/fw_bcm43455c0_ag.bin:$(TARGET_COPY_OUT_VENDOR)/firmware/fw_bcmdhd.bin \
     hardware/goodcom/firmware/BCM43455/nvram_bcm43455.txt:$(TARGET_COPY_OUT_VENDOR)/etc/wifi/bcmdhd.cal \
-    hardware/goodcom/firmware/BCM43455/p2p_supplicant.conf:$(TARGET_COPY_OUT_VENDOR)/etc/wifi/p2p_supplicant.conf
+    hardware/goodcom/firmware/BCM43455/p2p_supplicant.conf:$(TARGET_COPY_OUT_VENDOR)/etc/wifi/p2p_supplicant.conf \
+    hardware/goodcom/bluetooth/gocsdk:/system/bin/gocsdk \
+    hardware/goodcom/bluetooth/libGbtsTask.so:/system/lib/libGbtsTask.so \
+    hardware/goodcom/bluetooth/ring.mp3:system/ring.mp3
```

添加开机启动`gocsdk`服务：

```diff
on boot
     start mediadrm
     start media
     start drm
+    start gocsdk

+service gocsdk /system/bin/gocsdk
+    class main
+    user root
+    group root
+    disabled
+    oneshot
```

### 4. 添加 BT 权限

一般来说没有其他别的技巧，需要不停的烧录并检查`AVC`中关于`gocsdk`的禁止信息：

```text
type=1400 audit(1609830555.552:36): avc: denied { setuid } for comm="ping" capability=7 scontext=u:r:gocsdk:s0 tcontext=u:r:gocsdk:s0 tclass=capability permissive=1
type=1400 audit(1609830555.564:37): avc: denied { create } for comm="ping" scontext=u:r:gocsdk:s0 tcontext=u:r:gocsdk:s0 tclass=icmp_socket permissive=1
type=1400 audit(1609830555.568:38): avc: denied { write } for comm="ping" name="dnsproxyd" dev="tmpfs" ino=10712 scontext=u:r:gocsdk:s0 tcontext=u:object_r:dnsproxyd_socket:s0 tclass=sock_file permissive=1
type=1400 audit(1609830555.568:39): avc: denied { connectto } for comm="ping" path="/dev/socket/dnsproxyd" scontext=u:r:gocsdk:s0 tcontext=u:r:netd:s0 tclass=unix_stream_socket permissive=1
type=1400 audit(1609830555.576:40): avc: denied { create } for comm="ping" scontext=u:r:gocsdk:s0 tcontext=u:r:gocsdk:s0 tclass=udp_socket permissive=1
type=1400 audit(1609830555.576:43): avc: denied { use } for comm="Binder:397_2" path="socket:[20803]" dev="sockfs" ino=20803 scontext=u:r:netd:s0 tcontext=u:r:gocsdk:s0 tclass=fd permissive=1
type=1400 audit(1609830600.892:52): avc: denied { read write } for comm="Binder:397_2" path="socket:[20453]" dev="sockfs" ino=20453 scontext=u:r:netd:s0 tcontext=u:r:gocsdk:s0 tclass=udp_socket permissive=1
type=1400 audit(1609830600.892:53): avc: denied { getopt } for comm="Binder:397_2" scontext=u:r:netd:s0 tcontext=u:r:gocsdk:s0 tclass=udp_socket permissive=1
type=1400 audit(1609830560.672:48): avc: denied { create } for comm="ping" scontext=u:r:gocsdk:s0 tcontext=u:r:gocsdk:s0 tclass=icmp_socket permissive=1
type=1400 audit(1609830595.864:49): avc: denied { setuid } for comm="ping" capability=7 scontext=u:r:gocsdk:s0 tcontext=u:r:gocsdk:s0 tclass=capability permissive=1
type=1400 audit(1609830595.868:50): avc: denied { write } for comm="ping" name="fwmarkd" dev="tmpfs" ino=10719 scontext=u:r:gocsdk:s0 tcontext=u:object_r:fwmarkd_socket:s0 tclass=sock_file permissive=1
type=1400 audit(1609830595.920:51): avc: denied { write } for comm="ping" name="dnsproxyd" dev="tmpfs" ino=10712 scontext=u:r:gocsdk:s0 tcontext=u:object_r:dnsproxyd_socket:s0 tclass=sock_file permissive=1
type=1400 audit(1609830627.468:55): avc: denied { create } for comm="start_auth_from" scontext=u:r:gocsdk:s0 tcontext=u:r:gocsdk:s0 tclass=tcp_socket permissive=1
```

![sepolicy权限添加万用公式][add_sepolicy_general_formula]

仿照`vold`的`te`文件，添加如下`gocsdk`的`te`文件：

```text
device/fsl/imx8q/sepolicy/gocsdk.te
system/sepolicy/public/gocsdk.te
system/sepolicy/private/gocsdk.te
system/sepolicy/prebuilts/api/29.0/public/gocsdk.te
system/sepolicy/prebuilts/api/29.0/private/gocsdk.te
system/sepolicy/prebuilts/api/28.0/public/gocsdk.te
system/sepolicy/prebuilts/api/28.0/private/gocsdk.te
system/sepolicy/prebuilts/api/27.0/public/gocsdk.te
system/sepolicy/prebuilts/api/27.0/private/gocsdk.te
system/sepolicy/prebuilts/api/26.0/public/gocsdk.te
system/sepolicy/prebuilts/api/26.0/private/gocsdk.te
```

通常`prebuilts`目录下面的文件与`system/sepolicy/`的文件相同，只不过需要区分`public`和`private`的区别罢了。

其中`device/<board>/gocsdk.te`主要用于添加`allow`权限，`system/<public>/gocsdk.te`主要用于声明相关`type`，`system/<private>/gocsdk.te`主要用于声明相关`typeattribute`，这3个文件都可以添加`allow`权限，不过倾向于在`device/<board>/gocsdk.te`中添加，以免还需要同步到`prebuilts`目录下面去。

### 5. 常见权限问题

比较常见的是添加了的`allow`权限与系统中其他的`neverallow`权限冲突：
```bash
libsepol.report_failure: neverallow on line 999 of system/sepolicy/public/domain.te (or line 12486 of policy.conf) violated by allow gocsdk gocsdk_exec:file { read getattr map execute entrypoint open };
libsepol.report_failure: neverallow on line 971 of system/sepolicy/public/domain.te (or line 12408 of policy.conf) violated by allow gocsdk gocsdk_exec:file { execute };
libsepol.check_assertions: 2 neverallow failures occurred
Error while expanding policy
```
往往需要前往相应的te文件中，在`neverallow`语句中将其过滤。

然而修改系统中其他的te文件还需要保持`prebuilts`目录下相应文件与其保持同步，否则会出现如下错误：

```bash
Files system/sepolicy/prebuilts/api/29.0/public/domain.te and system/sepolicy/public/domain.te differ
```

但是有时候没有`neverallow`的冲突后，也会存在未知类型等错误，此时需要确认相关新添加的te文件如上文中所述的分布。

```bash
system/sepolicy/public/domain.te:971:ERROR 'unknown type gocsdk_exec' at token ';' on line 12434:
```

![sepolicy问题原因][cause_of_sepolicy_problem]

即便添加了`allow`权限，`avc`日志中还是会报出相关错误，这些错误的`tcontext`都会带有`c512,c768`的内容。经过检查发现需要在定义`gocsdk`类型时添加`mlstrustedsubject`属性。

```te
type gocsdk, domain, coredomain, mlstrustedsubject;
```

但是仍然会发现无法打开声卡文件节点，由于添加权限过程太过漫长，现记录添加打开声卡节点所需要的权限：

```te
allow gocsdk audio_device:chr_file { open read write ioctl };
allow gocsdk audio_device:dir { search };
```

发现需要的权限中有一个`procfsinspector`属性不能找到：

```log
avc: denied { read } for comm="gocsdk" scontext=u:r:gocsdk:s0 tcontext=u:r:procfsinspector:s0 tclass=file permissive=0
```

如果直接在`gocsdk.te`中添加，编译时会报无法找到`procfsinspector`属性的错误。在`system/sepolicy/`下面搜索也无法找到，最后发现在文件`packages/services/Car/car_product/sepolicy/private/procfsinspector.te`中添加即可：

```diff
+allow gocsdk procfsinspector:file { read };
```



参考资料：

[Android init.rc 添加自定义服务](https://blog.csdn.net/tq501501/article/details/103556837)

[selinux权限问题](https://blog.csdn.net/u011386173/article/details/83339770)

[Android 9 SELinux](https://www.jianshu.com/p/e95cd0c17adc)

[SELinux TE规则](https://wenku.baidu.com/view/402b8d8eb7360b4c2f3f646a.html)

[selinux security level引起的denied u:r:untrusted_app:s0:c512,c768问题](https://blog.csdn.net/nuanhua209/article/details/56481783)

[SEAndroid策略](https://blog.csdn.net/l173864930/article/details/17194899)

## 五. BT 功能测试

### 1. 权限添加流程

```mermaid
graph LR
   编译 --> 烧录 --> 日志 --> 修改 --> 编译
```

由于SELinux报错不是一次性全部显示的，所以需要不断地执行如上流程完成权限的添加，直到功能正常运行即可。

查看`AVC`日志命令：

```bash
mek_8q:/ # logcat | grep avc
```

### 2. 蓝牙功能测试

![蓝牙测试上位机][goodocom_bluetooth_test_app]

需要安装供应商提供的测试APP，并在界面中测试连接、扫描、设置、音乐、电话、联系人、最近通话等功能。

在遇到问题时，采集`gocsdk`服务的命令：

```bash
mek_8q:/ # logcat -s goc
```

然后提交给供应商用于分析问题。



[BA440_module]: /images/BA440_module.png
[BA440_top_layout]: /images/BA440_top_layout.png
[BA440_interface_diagram]: /images/BA440_interface_diagram.png
[BA440_schematic_diagram]: /images/BA440_schematic_diagram.png
[wpa_cli_connect_wifi_error]: /images/wpa_cli_connect_wifi_error.png
[wifi_limited_connection]: /images/wifi_limited_connection.png
[p2p_wifi_direct_example]: /images/p2p_wifi_direct_example.png
[p2p_test_100_result]: /images/p2p_test_100_result.png
[supplier_needed_header_files]: /images/supplier_needed_header_files.png
[supplier_needed_library_files]: /images/supplier_needed_library_files.png
[add_sepolicy_general_formula]: /images/add_sepolicy_general_formula.png
[cause_of_sepolicy_problem]: /images/cause_of_sepolicy_problem.png
[goodocom_bluetooth_test_app]: /images/goodocom_bluetooth_test_app.png
