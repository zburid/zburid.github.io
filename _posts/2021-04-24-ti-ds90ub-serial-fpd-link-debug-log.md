---
layout: post
title:  "FPD-Link相关功能调试记录"
date:   2021-04-24 12:32:42 +0800
categories: notes
description: "FPD-Link芯片DS90UB941/8及其相关功能的调试记录"
author: zburid
tags:   FPD-Link MIPI TI TP Goodix iMX8
typora-root-url: ..
mermaid: true
---

### 一、`FPD-Link`简介

[**`FPD-Link`**][FPD-Link-overview]全称为`Flat panel display link`，目前版本为`FPD-Link III`，其旨要在于通过更少的导线在汽车系统中快速传输高分辨率、未压缩的数据，常被应用于汽车领域用于点对点传输视频数据。该接口可通过低成本电缆如双绞线（`STP`）或同轴电缆（`COAX`）传输**数字高清视频**和**双向控制信道**。

借助 `FPD-Link` 串行器（`Serializer`）和解串器（`Deserializer`）可以为汽车系统中的各种视频接口（包括用于高级驾驶辅助系统 `ADAS`的摄像头`Camera`和信息娱乐系统`IVI`显示屏`Display`）优化高分辨率信号的设计和传输。

### 二、功能需求

我们采用[DS90UB941AS-Q1][DS90UB941AS-Q1-datasheet]和[DS90UB948-Q1][DS90UB948-Q1-datasheet]作为分体机显示方案：

![DS90UB941应用][DS90UB941-application]

该方案中，显示屏幕（`OpenLDI`）与触摸屏（`I2C/GPIO`）连接在`DS90UB948`上，`DS90UB948`与`DS90UB941`通过`FPD-Link`连接，最后`DS90UB941`通过相关接口（`MIPI-DSI/I2C/GPIO`）与`SOC`相连。经过相关配置，在`I2C`总线上，`SOC`不仅可以与`DS90UB941`通信，还能与`DS90UB948`和触摸屏芯片通信。对于`GPIO`和`INT`也是同样的道理。

### 三、显示功能调试

#### 1、MIPI-DSI输出

首先需要实现`SOC`输出`MIPI-DSI`信号。由于`SOC`中`MIPI-DSI`与`OpenLDI`可能是复用在一起的，所以要确认好当前系统的输出信号类型，否则后续调试都是不能进行的。

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

#### 2、FPD-Link调试

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

查看当前的`0x0C`设备是什么设备，可以通过`dummp`其内部寄存器查看：

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

其中`DSI`寄存器需要间接访问，具体操作的方法如下：

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

通常其他硬件等方面配置正常的话，如上的操作基本上可以实现屏幕的显示。

#### 3、相关问题

由于`FPD-Link`在车载领域的广泛应用，`TI`已经总结了相关[调试流程][DS90UB941AS-Q1-DSI-Bringup-Guide]，按照如下流程即可实现对`FPD-Link`的快速调试：

![DS90UB941调试流程][DS90UB941-bringup-flow]

##### 3.1 不能显示图像

首先确认芯片配置的工作模式是否正常。



其次确认`FPD-Link`通路是否正常。

在没有`MIPI`信号或者不能正常显示的情况下，可以通过使用`PATGEN`的方法来调试：

```shell
i2cset -fy $i2cport $seraddr 0x56 0x00 b    # Bridge Clocking Mode: 0 DSI Clock, 1 Ext Clock, 2 Int Clock, 3 Ext ref Clock
i2cset -fy $i2cport $seraddr 0x65 0x40 b    # PATGEN_EXTCLK: external pixel clock
                                            # PATGEN_TSEL: Patgen uses external video timing
i2cset -fy $i2cport $seraddr 0x64 0x01 b    # Enable PATGEN/Colorbar/Checkerboard
```



最后确认`MIPI-DSI`输入信号是否正常。





##### 3.2 图像颜色异常

画面颜色有偏色异常。



画面颜色多为灰色异常。



##### 3.3 图像上下抖动



#### 4、驱动实现


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
	b[1] = data;                /* 要写入的数据拷 */

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



### 四、TP功能调试


```cpp
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

