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

如上所示`iMX8`中有两路`MIPI-DSI`输出信号，每一路`MIPI-DSI`配有一路`I2C`接口和两个`GPIO`管脚。先在`DTS`中配置`MIPI-DSI`输出：

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

参考`imx8qxp-mek-dsi-rm67191.dts`文件配置`MIIPI-DSI`输出：

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





#### 3、DS90UB94X驱动


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
[iMX8-MIPI-DSI]: /images/imx8_mipi_dsi_schematic.png

