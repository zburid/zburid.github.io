---
layout: post
title:  "FPD-Link相关功能调试记录"
date:   2021-04-24 12:32:42 +0800
categories: notes
description: "FPD-Link芯片DS90UB941/8及其相关功能的调试记录"
author: zburid
tags:   FPD-Link MIPI TI TP Goodix
typora-root-url: ..
mermaid: true
---

### 一、`FPD-Link`简介

**`FPD-Link`**全称为`Flat panel display link`，目前版本为`FPD-Link III`，常被应用于汽车领域用于点对点传输视频数据。该接口可通过双绞线（`STP`）或同轴电缆（`COAX`）的低成本电缆传输**数字高清视频**和**双向控制信道**。



### 二、功能需求















### 三、显示功能调试


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

	/* test mode */
#if 0
	ds90ub94x_write_reg(g_ds90ub94x->ds90ub941_i2c, 0x65, 0x08);
	ds90ub94x_write_reg(g_ds90ub94x->ds90ub941_i2c, 0x64, 0x15);
#endif
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



[FPD-LINK-III-learning-note]: https://zhuanlan.zhihu.com/p/328429295
[DS90UB941AS-Q1-DSI-Bringup-Guide]: https://www.ti.com/lit/pdf/snla356

