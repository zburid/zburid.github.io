---
layout: post
title:  "FPD-Link相关功能调试记录"
date:   2021-04-24 12:32:42 +0800
categories: notes
description: "FPD-Link芯片DS90UB941/8及其相关功能的调试记录"
author: zburid
tags:   FPD-Link MIPI TI TP Goodix iMX8
typora-root-url: ..
show:   true
mermaid: true
---

## 一、FPD-Link简介

[**FPD-Link**][FPD-Link-overview]全称为`Flat panel display link`，目前版本为`FPD-Link III`，其旨要在于通过更少的导线在汽车系统中快速传输高分辨率、未压缩的数据，常被应用于汽车领域用于点对点传输视频数据。该接口可通过低成本电缆如双绞线（`STP`）或同轴电缆（`COAX`）传输**数字高清视频**和**双向控制信道**。

借助 `FPD-Link` 串行器（`Serializer`）和解串器（`Deserializer`）可以为汽车系统中的各种视频接口（包括用于高级驾驶辅助系统 `ADAS`的摄像头`Camera`和信息娱乐系统`IVI`显示屏`Display`）优化高分辨率信号的设计和传输。

## 二、功能需求

我们采用[DS90UB941AS-Q1][DS90UB941AS-Q1-datasheet]和[DS90UB948-Q1][DS90UB948-Q1-datasheet]作为分体机显示方案：

![DS90UB941应用][DS90UB941-application]

该方案中，显示屏幕（`OpenLDI`）与触摸屏（`I2C/GPIO`）连接在`DS90UB948`上，`DS90UB948`与`DS90UB941`通过`FPD-Link`连接，最后`DS90UB941`通过相关接口（`MIPI-DSI/I2C/GPIO`）与`SOC`相连。经过相关配置，在`I2C`总线上，`SOC`不仅可以与`DS90UB941`通信，还能与`DS90UB948`和触摸屏芯片通信。对于`GPIO`和`INT`也是同样的道理。

## 三、显示功能调试

### 1、MIPI-DSI输出

首先需要实现`SOC`输出`MIPI-DSI`信号。由于`SOC`中`MIPI-DSI`与`OpenLDI`的端口可能是复用在一起的，所以要确认好当前系统的输出信号类型，否则后续调试都是不能进行的。

![iMX8 MIPI DSI原理图][iMX8-MIPI-DSI]

如上所示`SOC`中有两路`MIPI-DSI`输出信号，每一路`MIPI-DSI`配有一路`I2C`接口和两个`GPIO`管脚。先在`DTS`中配置`MIPI-DSI`输出：

`imx8x-mek.dtsi`中关闭默认的`OpenLDI`输出：

```diff
 &ldb1_phy {
-	status = "okay";
+	status = "disabled";
 };

 &ldb1 {
-	status = "okay";
+	status = "disabled";
 };

 &mipi0_dphy {
     status = "okay";
 };
```

参考`imx8qxp-mek-dsi-rm67191.dts`文件配置`MIPI-DSI`输出：

```diff
 &mipi0_dsi_host {
 	status = "okay";

+	panel@0 {
+		#address-cells = <1>;
+		#size-cells = <0>;
+
+		compatible = "test,panel";
+		reg = <0>;
+
+		port@0 {
+			reg = <0>;
+			panel0_in: endpoint {
+				remote-endpoint = <&mipi0_panel_out>;
+			};
+		};
+	};
+
  	ports {
  		port@1 {
  			reg = <1>;
 			mipi0_panel_out: endpoint {
-				remote-endpoint = <&adv7535_0_in>;
+				remote-endpoint = <&panel0_in>;
 			};
 		};
 	};
 };
```

参考供应商提供的面板说明书，在`kernel_imx/drivers/gpu/drm/panel/panel-simple.c`中添加需要的屏参：

```diff
+static const struct drm_display_mode test_mode = {
+	.clock = 81000,
+	.hdisplay = 1920,
+	.hsync_start = 1920 + 20,
+	.hsync_end = 1920 + 20 + 2,
+	.htotal = 1920 + 20 + 2 + 34,
+	.vdisplay = 1080,
+	.vsync_start = 1080 + 10,
+	.vsync_end = 1080 + 10 + 2,
+	.vtotal = 1080 + 10 + 2 + 4,
+	.vrefresh = 60,
+	.flags = DRM_MODE_FLAG_NHSYNC | DRM_MODE_FLAG_NVSYNC,
+};
+
+static const struct panel_desc_dsi test_panel = {
+	.desc = {
+		.modes = &test_mode,
+		.num_modes = 1,
+		.bpc = 8,
+		.size = {
+			.width = 62,
+			.height = 110,
+		},
+	},
+	.flags = MIPI_DSI_MODE_VIDEO,
+	.format = MIPI_DSI_FMT_RGB888,
+	.lanes = 4,
+};
+
 static const struct of_device_id dsi_of_match[] = {
 	{
 		.compatible = "auo,b080uan01",
@@ -3744,6 +3773,9 @@ static const struct of_device_id dsi_of_match[] = {
 	}, {
 		.compatible = "osddisplays,osd101t2045-53ts",
 		.data = &osd101t2045_53ts
+	}, {
+		.compatible = "test,panel",
+		.data = &test_panel
 	}, {
 		/* sentinel */
 	}
```

重新编译内核并烧录，通过日志可以确认`MIPI-DSI`是否正常工作：

```log
[    7.228793] imx-drm display-subsystem: bound imx-drm-dpu-bliteng.2 (ops dpu_bliteng_ops)
[    7.237337] imx-drm display-subsystem: bound imx-dpu-crtc.0 (ops dpu_crtc_ops)
[    7.244934] imx-drm display-subsystem: bound imx-dpu-crtc.1 (ops dpu_crtc_ops)
[    7.252678] imx-drm display-subsystem: bound 56228000.dsi_host (ops nwl_dsi_component_ops)
[    7.261331] imx-drm display-subsystem: bound 56248000.dsi_host (ops nwl_dsi_component_ops)
```

如果驱动加载失败，日志会有提示`bound`失败的报错。

```text
mek_8q:/ # ls sys/class/drm/card1/
card1-DSI-1 card1-DSI-2 consumers dev device power subsystem suppliers uevent
mek_8q:/ # ls dev/dri/
card0 card1 renderD128 renderD129
```

通过如上命令即可查看到系统中是否创建了显卡设备。如果创建成功，即可通过`Total Control`或者`scrcpy`等投屏工具，实现从`adb`获取当前显示界面。

### 2、FPD-Link调试

通常，`DS90UB941`与`SOC`之间通过相应的`MIPI-DSI-I2C`相连。首先确保`I2C`是打开的：

```dts
&i2c0_mipi_lvds0 {
        #address-cells = <1>;
        #size-cells = <0>;
        pinctrl-names = "default";
        pinctrl-0 = <&pinctrl_i2c0_mipi_lvds0>;
        clock-frequency = <100000>;
        status = "okay";
};
```

通过`i2c-tools`工具包中的命令检测`I2C`总线是否生成：

```shell
mek_8q:/ # i2cdetect -l
i2c-1   i2c             i2c-rpmsg-adapter                       I2C Adapter
i2c-17  i2c             56246000.i2c                            I2C Adapter
i2c-15  i2c             i2c-rpmsg-adapter                       I2C Adapter
i2c-18  i2c             58226000.i2c                            I2C Adapter
i2c-16  i2c             56226000.i2c                            I2C Adapter
i2c-5   i2c             i2c-rpmsg-adapter                       I2C Adapter
```

查看当前`I2C`总线上“挂载”的所有设备：

```shell
mek_8q:/ # i2cdetect -y 16
Probe chips 0x00-0x7f on bus 16? (Y/n):
     0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
00: -- -- -- -- -- -- -- -- -- -- -- -- 0c -- -- --
10: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
20: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
30: -- -- -- UU -- -- -- -- -- -- -- -- -- -- -- --
40: -- -- -- -- -- -- -- -- -- -- -- -- UU -- -- --
50: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
60: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
70: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
```

想要查看当前的`0x0C`设备是什么设备，可以通过`dummp`其内部寄存器查看：

```shell
mek_8q:/ # i2cdump -f -y 16 0x0c
     0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f    0123456789abcdef
00: 18 00 00 92 00 00 5c 00 00 01 0e 00 27 30 00 00    ?..?..\..??.'0..
10: 00 00 00 8b 00 00 fe 1e 7f 7f 01 00 00 00 01 00    ...?..?????...?.
20: 0b 00 25 00 00 00 00 00 01 20 20 a0 00 00 a5 5a    ?.%.....?  ?..?Z
30: 00 09 00 05 0c 00 00 00 00 00 00 00 00 00 81 02    .?.??.........??
40: 10 90 00 00 00 00 00 00 00 00 00 00 00 00 00 8c    ??.............?
50: 16 00 00 00 02 00 00 02 00 00 d9 00 07 06 44 31    ?...?..?..?.??D1
60: 22 02 00 00 10 00 00 00 00 00 00 00 00 00 20 00    "?..?......... .
70: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 7f 00    ..............?.
80: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00    ................
90: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00    ................
a0: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00    ................
b0: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00    ................
c0: 00 00 82 00 38 00 00 64 40 00 00 00 00 02 ff 00    ..?.8..d@....??.
d0: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00    ................
e0: 00 00 82 00 28 08 00 00 00 00 00 00 00 02 00 00    ..?.(?.......?..
f0: 5f 55 42 39 34 31 00 00 00 00 00 00 00 00 00 00    _UB941..........
```

能够看到`0x0C`设备即是`DS90UB941`：

```shell
i2cport=16
seraddr=0x0c
```

查看芯片手册可知`DSI`寄存器需要间接访问，具体操作的方法如下：

```shell
function ser_dsireg_write(){
    # UB941 device DSI registers write
    # Args:
    #   $1: port    : 0/1
    #   $2: addr    : DSI registers indirect address to set
    #   $3: value   : DSI registers indirect value to set
    port=0x04
    if [ $1 -eq 1 ]; then
        port=0x08
    fi
    i2cset -fy $i2cport $seraddr 0x40 $port b
    i2cset -fy $i2cport $seraddr 0x41 $2 b  # IND_ACC_ADDR
    i2cset -fy $i2cport $seraddr 0x42 $3 b  # IND_ACC_DATA
}

function ser_dsireg_dump(){
    # UB941 device DSI registers dump
    # Args:
    #   $1: port    : 0/1
    port=0x07
    if [ $1 -eq 1 ]; then
        port=0x0B
    fi
    i2cset -fy $i2cport $seraddr 0x40 $port b
    i2cset -fy $i2cport $seraddr 0x41 0x00 b
    echo "Dumped DSI"$1" registers here:"
    echo "     0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f"
    for i in $(seq 0 3)
    do
        echo -n $i"0: "
        for j in $(seq 0 15)
        do
            res=`i2cget -fy 17 0x0c 0x42`
            echo -n ${res: 2: 2}" "
        done
        echo " "
    done
}
```

然后可以根据芯片手册配置如下：

```shell
i2cset -fy $i2cport $seraddr 0x01 0x0f b    # Reset DSI/DIGITLE
i2cset -fy $i2cport $seraddr 0x1E 0x01 b    # Select FPD-Link III Port 0
i2cset -fy $i2cport $seraddr 0x03 0xBA b    # Enable FPD-Link I2C pass through
i2cset -fy $i2cport $seraddr 0x5B 0x0B b    # FPD3_TX_MODE=Dual, Align on DE
i2cset -fy $i2cport $seraddr 0x4F 0x0C b    # DSI Continuous Clock Mode, DSI 4 lanes

ser_dsireg_write 0 0x05 0x14                # Set DSI0 TSKIP_CNT value

i2cset -fy $i2cport $seraddr 0x01 0x00 b    # Release DSI/DIGITLE reset
```

除此之外，还需要配置`DS90UB948`使能相应的`GPIO`输出：

![DS90UB948 GPIO接口][DS90UB948-GPIO-INTERFACE]

通过查看`DS90UB948`中`GPIO`的手册：

![948 GPIO 寄存器手册][ds90ub948_gpio_register_manual]

写入相关的值使能`LCD`显示和背光功能：

```shell
i2cset -fy $i2cport $desaddr 0x1A 0x09 b    # lcd_en：使能LCD的输入
i2cset -fy $i2cport $desaddr 0x1E 0x90 b    # lcd_led_pwm：背光显示
i2cset -fy $i2cport $desaddr 0x1F 0x09 b    # lcd_led_en：背光显示
```

通常来说，硬件等方面配置正常的话，如上的操作基本上可以实现屏幕的显示。

### 3、相关问题

由于`FPD-Link`在车载领域的广泛应用，`TI`已经总结了相关[调试指南][DS90UB941AS-Q1-DSI-Bringup-Guide]，按照如下流程即可实现对`FPD-Link`的快速调试：

![DS90UB941调试流程][DS90UB941-bringup-flow]

#### 3.1 不能显示图像

* 首先确认芯片配置的工作模式是否正常：

根据实际需求，通过配置`MODE_SEL[1:0]`上下拉电阻来选择`DS90UB941`的工作模式：

![DS90UB941 MODE_SEL配置][DS90UB941-MODE_SEL-configure]

* 其次确认`FPD-Link`通路是否正常：

在没有`MIPI`信号或者不能正常显示的情况下，可以通过使用`PATGEN`的方法来调试`FPD-Link`通路：

```shell
i2cset -fy $i2cport $seraddr 0x56 0x00 b    # Bridge Clocking Mode: 0 DSI Clock
                                            # 1 Ext Clock, 2 Int Clock, 3 Ext ref Clock
i2cset -fy $i2cport $seraddr 0x65 0x40 b    # PATGEN_EXTCLK: external pixel clock
                                            # PATGEN_TSEL: Patgen uses external video timing
i2cset -fy $i2cport $seraddr 0x64 0x01 b    # Enable PATGEN/Colorbar/Checkerboard
```

可以选择彩条、（国际象棋）棋盘或者其他类型的`PATGEN`。通常来说，配置好`DS90UB941`后，只要`FPD-Link`通路没有问题，就能正常在显示屏幕上显示`PATGEN`图案。一般选择棋盘可以查看显示界面是否抖动，彩条可以查看显示界面颜色是否正常。

* 最后确认`MIPI-DSI`信号是否正常：

通过官方推荐的`DS90UB941`调试流程，可以采用`PATGEN`的方法验证`MIPI-DSI`信号是否正常：

    1）PATGEN使用内部时序和内部时钟
    2）PATGEN使用内部时序和外部DSI时钟
    3）PATGEN使用外部DSI时序和外部DSI时钟

通过如上的步骤，看在哪一步的时候显示不正常了。如果只要是使用`MIPI-DSI`时钟就不能正常工作，说明需要使用相关工具检测`MIPI-DSI`信号。通常`SOC`输出的`MIPI-DSI`信号都能满足芯片的接收，一般情况下只需要确认输出信号不是`OpenLDI`即可。

如果以上各项操作均未发现问题，请检查**`LVDS`排线线序**是否正常。

#### 3.2 图像颜色异常

* 画面颜色有偏色异常且画面轻微抖动：

通常需要检测解串器上相关`OpenLDI`差分数据`PIN`脚的状态，**短路**、**断路**、**对地**等硬件问题都会造成颜色偏差和图像抖动的问题。

* 画面颜色有灰色异常：

通常需要检测`OpenLDI`输出数据格式是否与屏幕参数相匹配，`OpenLDI`可以配置为`JEIDA`时序和`VESA`时序：

![DS90UB948 OpenLDI输出格式][DS90UB948-OpenLDI-mapping]

通过设置`DS90UB948`上`MODE_SEL0`上的上下拉电阻，即可调整`MAPSEL`：

![DS90UB948 MODE_SEL0配置][DS90UB948-MODE_SEL0-configure]

#### 3.3 图像上下抖动（Jitter）

* 只有使用`MIPI-DSI`时钟的时候才会抖动：

此时需要考虑`MIPI-DSI`时钟信号等是否与`DS90UB941`中`DSI`接收器的配置一致，具体可以参考官网的[调试指南][DS90UB941AS-Q1-DSI-Bringup-Guide]文档重新配置相关寄存器：

配置`TSKIP_CNT`：


$$
T_{SKIP\_CNT}=Round(65*F_{DSI}-5)
$$


```shell
ser_dsireg_write 0 0x05 0x20                # T-SKIP = 0x20/0x04
```

配置`Sync Width for Event Mode/Burst Mode`：

```shell
ser_dsireg_write 0 0x20 0x67                # DSI_SYNC_PULSES = 0
ser_dsireg_write 0 0x30 0x00                # Hsync Pulse Width [9:8]
ser_dsireg_write 0 0x31 0x20                # Hsync Pulse Width [7:0]
ser_dsireg_write 0 0x32 0x00                # Vsync Pulse Width [9:8]
ser_dsireg_write 0 0x33 0x04                # Vsync Pulse Width [7:0]
```

* 任何情况下包括采用内部时钟时序的`PATGEN`都会存在抖动：

```shell
i2cset -fy $i2cport $deraddr 0x01 0x01 b    # Reset DS90UB948
```

目前遇到的这种情况下需要在一定时间内对`DS90UB948`复位一下即可。



### 4、驱动实现


```cpp
// vendor/nxp-opensource/kernel_imx/drivers/gpu/drm/bridge/ds90ub94x.c

#include <linux/i2c.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/delay.h>

#define DS90UB941_I2C_ADDR 0x0c
#define DS90UB948_I2C_ADDR 0x2c

struct ds90ub94x {
	struct i2c_client *ds90ub941_i2c;
	struct i2c_client *ds90ub948_i2c;
};

static struct ds90ub94x *g_ds90ub94x;

static void ds90ub94x_write_reg(struct i2c_client *client, u8 reg, u8 data)
{
	int ret;
	u8 b[2];
	struct i2c_msg msg;

	b[0] = reg;                 /* 寄存器首地址 */
	b[1] = data;                /* 要写入的数据 */

	msg.addr = client->addr;    /* i2c地址 */
	msg.flags = 0;              /* 标记为写数据 */
	msg.buf = b;                /* 要写入的数据缓冲区 */
	msg.len = 2;                /* 要写入的数据长度 */

	ret = i2c_transfer(client->adapter, &msg, 1);
	if(ret != 1)
		printk("i2c write failed: ret=%d reg=%02x\n",ret, reg);
}

static void ds90ub94x_display_setting(void)
{
	ds90ub94x_write_reg(g_ds90ub94x->ds90ub941_i2c, 0x01, 0x0f); /* Reset DSI/DIGITLE */
	ds90ub94x_write_reg(g_ds90ub94x->ds90ub941_i2c, 0x03, 0xBA); /* Enable FPD-Link I2C pass through */
	ds90ub94x_write_reg(g_ds90ub94x->ds90ub941_i2c, 0x1E, 0x01); /* Select FPD-Link III Port 0 */
	ds90ub94x_write_reg(g_ds90ub94x->ds90ub941_i2c, 0x5B, 0x0B); /* FPD3_TX_MODE=Dual, Align on DE */
	ds90ub94x_write_reg(g_ds90ub94x->ds90ub941_i2c, 0x4F, 0x8C); /* DSI Continuous Clock Mode,DSI 4 lanes */
	ds90ub94x_write_reg(g_ds90ub94x->ds90ub941_i2c, 0x40, 0x04); /* Set DSI0 TSKIP_CNT value */
	ds90ub94x_write_reg(g_ds90ub94x->ds90ub941_i2c, 0x41, 0x05);
	ds90ub94x_write_reg(g_ds90ub94x->ds90ub941_i2c, 0x42, 0x14);
	ds90ub94x_write_reg(g_ds90ub94x->ds90ub941_i2c, 0x01, 0x00); /* Release DSI/DIGITLE reset */

	ds90ub94x_write_reg(g_ds90ub94x->ds90ub948_i2c, 0x01, 0x01); /* ds90ub948 reset */
	usleep_range(10000, 11000);	/* time cannot be too short */
	ds90ub94x_write_reg(g_ds90ub94x->ds90ub948_i2c, 0x1A, 0x09); /* lcd_en：使能LCD的输入 */
	ds90ub94x_write_reg(g_ds90ub94x->ds90ub948_i2c, 0x1E, 0x90); /* lcd_led_en：背光显示 */
	ds90ub94x_write_reg(g_ds90ub94x->ds90ub948_i2c, 0x1F, 0x09);
}

static int ds90ub94x_probe(struct i2c_client *client, const struct i2c_device_id *id)
{
	struct device *dev = &client->dev;
	struct ds90ub94x *ds90ub94x;

	ds90ub94x = devm_kzalloc(dev, sizeof(*ds90ub94x), GFP_KERNEL);
	if (!ds90ub94x)
		return -ENOMEM;

	ds90ub94x->ds90ub941_i2c = client;
	ds90ub94x->ds90ub948_i2c = i2c_new_dummy(client->adapter, DS90UB948_I2C_ADDR);
	if (!ds90ub94x->ds90ub948_i2c) {
		return -ENODEV;
	}

	i2c_set_clientdata(client, ds90ub94x);

	g_ds90ub94x = ds90ub94x;

	/* config display */
	ds90ub94x_display_setting();

	return 0;
}

static int ds90ub94x_remove(struct i2c_client *client)
{
	return 0;
}

static const struct of_device_id ds90ub94x_of_match[] = {
	{
		.compatible = "ti,ds90ub94x"
	},
	{ /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, ds90ub94x_of_match);

static struct i2c_driver ds90ub94x_driver = {
	.driver = {
		.name = "ds90ub94x",
		.of_match_table = ds90ub94x_of_match,
	},
	.probe = ds90ub94x_probe,
	.remove = ds90ub94x_remove,
};
module_i2c_driver(ds90ub94x_driver);

MODULE_DESCRIPTION("TI. DS90UB941/DS90UB948 SerDer bridge");
MODULE_LICENSE("GPL");
```



## 四、TP功能调试

采用`Goodix`（[汇顶科技][goodix-official-website]）的`GT9XX`系列触摸屏，通过`FPD-Link`传输`I2C`和`GPIO/IRQ`信号，来获取触摸中断信号并控制`TP`复位：

![Goodix触摸屏接口座子][GOODIX-TP-SEAT]



### 1、TP调试

先用命令配置寄存器值，实现远程GPIO的功能控制。再实现远程透传，实现触摸驱动功能。

#### 1.1 测试GPIO

首先需要将需要的`GPIO`管脚配置为复用为普通`IO`口：

```diff
pinctrl_i2c0_mipi_lvds0: mipi_lvds0_i2c0_grp {
    fsl,pins = <
        IMX8QXP_MIPI_DSI0_I2C0_SCL_MIPI_DSI0_I2C0_SCL     0xc6000020
        IMX8QXP_MIPI_DSI0_I2C0_SDA_MIPI_DSI0_I2C0_SDA     0xc6000020
-       IMX8QXP_MIPI_DSI0_GPIO0_01_LSIO_GPIO1_IO28        0x00000020
+       IMX8QXP_MIPI_DSI0_GPIO0_00_LSIO_GPIO1_IO27        0x00000020
+       IMX8QXP_MIPI_CSI0_I2C0_SCL_LSIO_GPIO3_IO05        0x00000020
    >;
};
```

编译烧写固件，通过`export`来控制`pin`脚电平，确认`pin`脚配置可用：

```shell
cd sys/class/gpio/
#lsio_gpio1 27
echo 59 > export && cd gpio59
echo  out > direction
echo 1 > value
echo 0 > value
echo 59 > unexport

cd sys/class/gpio/
#lsio_gpio3 5
echo 101 > export && cd gpio101
echo  out > direction
echo 1 > value
echo 0 > value
echo 60 > unexport
```

通过配置`DS90UB948`寄存器，设置与`TP`相连的`948`管脚的电平信号如`TP`说明书中所要求的时序：

* 设定地址为`0x28/0x29`的复位时序：

  ![GT9XX 0x28/0x29 复位时序图][gt9xx_reset_sequence_0x2x]

* 设定地址为`0xBA/0xBB`的复位时序：

  ![GT9XX 0xBA/0xBB 复位时序图][gt9xx_reset_sequence_0xbx]

```shell
# 初始化 TP 配置其 I2C 地址 0x5d
i2cset -fy $i2cport $desaddr 0x1D 0x01 b
i2cset -fy $i2cport $desaddr 0x1E 0x91 b
sleep 0.5
i2cset -fy $i2cport $desaddr 0x1D 0x09 b

# 初始化 TP 配置其 I2C 地址 0x14
i2cset -fy $i2cport $desaddr 0x1D 0x01 b
i2cset -fy $i2cport $desaddr 0x1E 0x91 b
sleep 0.2
i2cset -fy $i2cport $desaddr 0x1E 0x99 b
sleep 0.2
i2cset -fy $i2cport $desaddr 0x1D 0x09 b
sleep 0.5

# 检测总线上是否有 TP 地址
i2cdetect -y 16
     0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
00:          -- -- -- -- -- -- -- -- -- UU -- -- --
10: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
20: -- -- -- -- -- -- -- -- -- -- -- -- UU -- -- --
30: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
40: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
50: -- -- -- -- -- -- -- -- -- -- -- -- -- 5d -- --
60: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
70: -- -- -- -- -- -- -- --
```

#### 1.2 测试透传

配置远程`GPIO`控制功能，即`SOC`控制读取`GPIO`透传到`TP`侧：

```text
SOC <=> 941 <=> 948 <=> TP
```

![DS90UB94X 前后向通道][ds90ub94x_forward_back_channel]

根据芯片手册，配置寄存器实现通路输入输出：

```shell
#gpio0打通成功
i2cset -fy $i2cport $seraddr 0x0D 0x03 b
i2cset -fy $i2cport $desaddr 0x1D 0x05 b

#gpio1打通成功
i2cset -fy $i2cport $seraddr 0x0E 0x03 b
i2cset -fy $i2cport $desaddr 0x1E 0x95 b
```

再通过`export`测试远程透传`GPIO`功能是否成功。



### 2、驱动实现

#### 2.1 获取驱动

```shell
$ git clone https://github.com/goodix/gt9xx_driver_android
```

获取`github`上最新的驱动程序，并将其放置到`vendor/nxp-opensource/kernel_imx/drivers/input/touchscreen/`下，修改如下：

```diff
diff --git vendor/nxp-opensource/kernel_imx/arch/arm64/configs/imx_v8_android_defconfig
 CONFIG_INPUT_TOUCHSCREEN=y
-CONFIG_TOUCHSCREEN_ATMEL_MXT=m
-CONFIG_TOUCHSCREEN_SYNAPTICS_DSX_I2C=m
+CONFIG_TOUCHSCREEN_ATMEL_MXT=n
+CONFIG_TOUCHSCREEN_SYNAPTICS_DSX_I2C=n
+CONFIG_TOUCHSCREEN_GT9XX=y
 CONFIG_INPUT_MISC=y
 CONFIG_INPUT_UINPUT=y

diff --git vendor/nxp-opensource/kernel_imx/drivers/input/touchscreen/Kconfig
 source "drivers/input/touchscreen/synaptics_dsx/Kconfig"
+source "drivers/input/touchscreen/gt9xx/Kconfig"
 endif
 source "drivers/input/touchscreen/focaltech_touch/Kconfig"

diff --git vendor/nxp-opensource/kernel_imx/drivers/input/touchscreen/Makefile
 obj-$(CONFIG_TOUCHSCREEN_RASPBERRYPI_FW)    += raspberrypi-ts.o
 obj-$(CONFIG_TOUCHSCREEN_IQS5XX)    += iqs5xx.o
+obj-$(CONFIG_TOUCHSCREEN_GT9XX)    +=  gt9xx/
```



#### 2.2 配置DTS

根据需要，配置`DTS`如下：

```dts
&i2c0_mipi_lvds0 {
    #address-cells = <1>;
    #size-cells = <0>;
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_i2c0_mipi_lvds0>;
    clock-frequency = <100000>;
    status = "okay";

    gt9xx-i2c@5d {
        compatible = "goodix,gt9xx";
        reg = <0x5d>;
        status = "okay";
        interrupt-parent = <&lsio_gpio3>;
        interrupts = <5 IRQ_TYPE_LEVEL_LOW>;
        reset-gpios = <&lsio_gpio1 27 GPIO_ACTIVE_HIGH>;
        irq-gpios = <&lsio_gpio3 5 IRQ_TYPE_LEVEL_LOW>;
        irq-flags = <2>;

        touchscreen-max-id = <11>;
        touchscreen-size-x = <1080>;
        touchscreen-size-y = <1920>;
        touchscreen-max-w = <512>;
        touchscreen-max-p = <512>;
        //touchscreen-key-map = <172>, <158>; /*KEY_HOMEPAGE=172, KEY_BACK=158，KEY_MENU=139*/

        goodix,type-a-report = <0>;
        goodix,driver-send-cfg = <0>;
        goodix,wakeup-with-reset = <0>;
        goodix,resume-in-workqueue = <0>;
        goodix,int-sync = <1>; /* don't modified it */
        goodix,swap-x2y = <1>;
        goodix,x-reverse = <1>;
        goodix,y-reverse = <1>;
        goodix,esd-protect = <0>;
        goodix,auto-update-cfg = <0>;
        goodix,power-off-sleep = <0>;
        goodix,pen-suppress-finger = <0>;
        goodix,cfg-group0 = [
            42 D0 02 00 05 05 75 01 01 0F 24
            0F 64 3C 03 05 00 00 00 02 00 00
            00 16 19 1C 14 8C 0E 0E 24 00 31
            0D 00 00 00 83 33 1D 00 41 00 00
            00 00 00 08 0A 00 2B 1C 3C 94 D5
            03 08 00 00 04 93 1E 00 82 23 00
            74 29 00 69 2F 00 5F 37 00 5F 20
            40 60 00 F0 40 30 55 50 27 00 00
            00 00 00 00 00 00 00 00 00 00 00
            00 00 00 00 00 00 00 14 19 00 00
            50 50 02 04 06 08 0A 0C 0E 10 12
            14 16 18 1A 1C 00 00 00 00 00 00
            00 00 00 00 00 00 00 00 00 00 1D
            1E 1F 20 21 22 24 26 28 29 2A 1C
            18 16 14 13 12 10 0F 0C 0A 08 06
            04 02 00 00 00 00 00 00 00 00 00
            00 00 00 00 00 00 00 00 9C 01];
    };
};
```



#### 2.2 适配驱动

由于TP驱动需要读取和设置远程`GPIO`状态，而远程`GPIO`读取设置函数需要由`DS90UB94X`驱动实现，所以需要在`DS90UB94X`驱动中`export`出来：


```cpp
// vendor/nxp-opensource/kernel_imx/drivers/gpu/drm/bridge/ds90ub94x.c
/* set remote gpio0 output */
void ds90ub94x_tp_rst_output(void)
{
	ds90ub94x_write_reg(g_ds90ub94x->ds90ub941_i2c, 0x0D, 0x03);
	ds90ub94x_write_reg(g_ds90ub94x->ds90ub948_i2c, 0x1D, 0x05);
}
EXPORT_SYMBOL(ds90ub94x_tp_rst_output);

/* set remote gpio0 input */
void ds90ub94x_tp_rst_input(void)
{
	ds90ub94x_write_reg(g_ds90ub94x->ds90ub941_i2c, 0x0D, 0x05);
	ds90ub94x_write_reg(g_ds90ub94x->ds90ub948_i2c, 0x1D, 0x03);
}
EXPORT_SYMBOL(ds90ub94x_tp_rst_input);

/* set remote gpio1 out */
void ds90ub94x_tp_int_output(void)
{
	ds90ub94x_write_reg(g_ds90ub94x->ds90ub941_i2c, 0x0E, 0x03);
	ds90ub94x_write_reg(g_ds90ub94x->ds90ub948_i2c, 0x1E, 0x95);
}
EXPORT_SYMBOL(ds90ub94x_tp_int_output);

/* set remote gpio1 input */
void ds90ub94x_tp_int_input(void)
{
	ds90ub94x_write_reg(g_ds90ub94x->ds90ub941_i2c, 0x0E, 0x05);
	ds90ub94x_write_reg(g_ds90ub94x->ds90ub948_i2c, 0x1E, 0x93);
}
EXPORT_SYMBOL(ds90ub94x_tp_int_input);

/* set remote i2c address */
void ds90ub94x_set_i2c(unsigned short addr)
{
	addr <<= 1;
	printk("addr = 0x%02x\n",addr);
	ds90ub94x_write_reg(g_ds90ub94x->ds90ub941_i2c, 0x07, addr);
	ds90ub94x_write_reg(g_ds90ub94x->ds90ub941_i2c, 0x08, addr);

	ds90ub94x_write_reg(g_ds90ub94x->ds90ub948_i2c, 0x08, addr);
	ds90ub94x_write_reg(g_ds90ub94x->ds90ub948_i2c, 0x10, addr);
}
EXPORT_SYMBOL(ds90ub94x_set_i2c);
```

最后修改`gt9xx.c`，实现对`TP`驱动的定制：

```diff
// vendor/nxp-opensource/kernel_imx/drivers/input/touchscreen/gt9xx/gt9xx.c

@@ -23,6 +23,7 @@
#include <linux/pinctrl/consumer.h>
#include <linux/input/mt.h>
#include "gt9xx.h"
+#include <linux/ds90ub94x.h>
#define GOODIX_COORDS_ARR_SIZE    4
#define PROP_NAME_SIZE        24
@@ -649,6 +661,7 @@ void gtp_int_output(struct goodix_ts_data *ts, int level)
     if (!ts->pdata->int_sync)
         return;
+    ds90ub94x_tp_int_output();
     if (level == 0) {
         if (ts->pinctrl.pinctrl)
             pinctrl_select_state(ts->pinctrl.pinctrl,
@@ -681,8 +694,10 @@ void gtp_int_sync(struct goodix_ts_data *ts, s32 ms)
         pinctrl_select_state(ts->pinctrl.pinctrl,
                      ts->pinctrl.int_input);
     } else if (gpio_is_valid(ts->pdata->irq_gpio)) {
+        ds90ub94x_tp_int_output();
         gpio_direction_output(ts->pdata->irq_gpio, 0);
         msleep(ms);
+        ds90ub94x_tp_int_input();
         gpio_direction_input(ts->pdata->irq_gpio);
     } else {
         dev_err(&ts->client->dev, "Failed sync int pin\n");
@@ -709,7 +724,8 @@ void gtp_reset_guitar(struct i2c_client *client, s32 ms)
         dev_warn(&client->dev, "reset failed no valid reset gpio");
         return;
     }

+    ds90ub94x_set_i2c(client->addr);
+    ds90ub94x_tp_rst_output();
     gpio_direction_output(ts->pdata->rst_gpio, 0);
     usleep_range(ms * 1000, ms * 1000 + 100);    /*  T2: > 10ms */
@@ -719,6 +735,7 @@ void gtp_reset_guitar(struct i2c_client *client, s32 ms)
     gpio_direction_output(ts->pdata->rst_gpio, 1);
     usleep_range(6000, 7000);        /*  T4: > 5ms */
+    ds90ub94x_tp_rst_input();
     gpio_direction_input(ts->pdata->rst_gpio);
     gtp_int_sync(ts, 50);
@@ -1470,6 +1487,7 @@ static int gtp_request_io_port(struct goodix_ts_data *ts)
             return -ENODEV;
         }
+        ds90ub94x_tp_int_input();
         gpio_direction_input(ts->pdata->irq_gpio);
         dev_info(&ts->client->dev, "Success request irq-gpio\n");
     }
@@ -1487,6 +1505,7 @@ static int gtp_request_io_port(struct goodix_ts_data *ts)
             return -ENODEV;
         }
+        ds90ub94x_tp_rst_input();
         gpio_direction_input(ts->pdata->rst_gpio);
         dev_info(&ts->client->dev,  "Success request rst-gpio\n");
     }
```



### 3、调试命令

* 查看中断请求记录，用于查看`TP`触摸中断

  ```shell
  cat /proc/interrupts
  ```

* 查看输入设备节点

  ```shell
  ls /dev/input/
  ```


* 查看输入设备的信息

  ```shell
  cat /proc/bus/input/devices
  ```

* 查看`event`上报信息

  ```shell
  getevent
  ```

* 查看触摸输入指针位置

  ```shell
  settings put system show_touches 1
  settings put system pointer_location 1
  ```


参考文档：

[FPD-Link III自学笔记][FPD-LINK-III-learning-note]



[FPD-Link-overview]: https://www.ti.com.cn/zh-cn/interface/fpd-link-serdes/overview.html
[FPD-LINK-III-learning-note]: https://zhuanlan.zhihu.com/p/328429295
[DS90UB941AS-Q1-DSI-Bringup-Guide]: https://www.ti.com/lit/pdf/snla356
[DS90UB941AS-Q1-datasheet]: http://www.ti.com/product/ds90ub941as-q1?qgpn=ds90ub941as-q1
[DS90UB948-Q1-datasheet]: http://www.ti.com/product/ds90ub948-q1?qgpn=ds90ub948-q1
[DS90UB941-application]: /images/ds90ub941_application.png
[DS90UB941-bringup-flow]: /images/ds90ub941_bringup_flow.png
[iMX8-MIPI-DSI]: /images/imx8_mipi_dsi_schematic.png
[DS90UB948-OpenLDI-mapping]: /images/ds90ub948_openldi_mapping.png
[DS90UB948-MODE_SEL0-configure]: /images/ds90ub948_mode_sel0_configure.png
[DS90UB941-MODE_SEL-configure]: /images/ds90ub941_mode_sel_configure.png

[goodix-official-website]: https://www.goodix.com/
[DS90UB948-GPIO-INTERFACE]: /images/ds90ub948-gpio-interface.png
[ds90ub948_gpio_register_manual]: /images/ds90ub948_gpio_register_manual.png
[GOODIX-TP-SEAT]: /images/imx8qxp-goodix-tp-seat.png
[gt9xx_reset_sequence_0x2x]: /images/gt9xx_reset_seq_0x2x.png
[gt9xx_reset_sequence_0xbx]: /images/gt9xx_reset_seq_0xbx.png
[ds90ub94x_forward_back_channel]: /images/ds90ub94x_forward_back_channel.png



