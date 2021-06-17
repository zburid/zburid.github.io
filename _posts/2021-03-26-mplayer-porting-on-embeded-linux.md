---
layout: post
title:  "MPlayer播放器移植"
date:   2021-03-26 16:48:16 +0800
categories: notes
description: "MPlayer播放器源码移植到嵌入式平台"
author: zburid
tags:   MPlayer Linux 嵌入式
typora-root-url: ..
show:   true
---

[MPlayer][mplayer-website]是一款开源多媒体播放器，以GNU通用公共许可证发布。它资源占用率低，无论是音频还是视频方面，支持的格式相当全面，支持的输出设备也很多，可以在各种主流操作系统中使用。

### 一、下载源码

在移植`MPlayer`之前除了需要下载`MPlayer`源码，还需要准备好`libmad`、`alsa-lib`相关库的源码。

#### 1. 下载`MPlayer`源码：

```bash
$ wget http://www.mplayerhq.hu/MPlayer/releases/MPlayer-1.4.tar.xz
$ tar -xvJf ./MPlayer-1.4.tar.xz
```

`MPlayer-1.4`编译之后的可执行文件可能会比较大（未优化下大约有50多MB），如果对资源比较敏感的话，可以采用`MPlayer-1.0`：

```bash
$ wget http://www.mplayerhq.hu/MPlayer/releases/MPlayer-1.0rc3.tar.bz2
$ tar -xvjf ./MPlayer-1.0rc3.tar.bz2
```

#### 2. 下载[`libmad`][libmad-website]源码：

```bash
$ wget https://sourceforge.net/projects/mad/files/libmad/0.15.1b/libmad-0.15.1b.tar.gz/download
$ tar -xvzf ./libmad-0.15.1b.tar.gz
```

#### 3. 下载[`alsa-lib`][alsa-website]源码：

```bash
$ git clone https://github.com/alsa-project/alsa-lib.git
```

`github`上的是最新的`alsa-lib`源码，如需要旧的源码可以采用如下链接资源：

```bash
$ wget ftp://ftp.alsa-project.org/pub/lib/alsa-lib-1.2.2.tar.bz2
```

### 二、交叉编译源码

#### 1. 交叉编译`libmad`源码：

```bash
$ ./configure \
--enable-fpm=arm \
--host= \
--enable-shared \
--enable-static \
--disable-debugging \
--prefix=/sdk/mplayer/install \
CC=arm-ca9-linux-gnueabihf-gcc
```

执行`configure`成功以后，我们打开`Makefile`，如果找到`-fforce-mem`，就将其删除。然后执行`make`后就能生成输出：

```bash
$ make && make install
```

生成文件输出到`/sdk/mplayer/install`目录下面。

#### 2. 交叉编译`alsa-lib`源码

如果没有`configure`文件，需要先执行`autoreconf`生成：

```bash
$ autoreconf -vi
```

编译生成`alsa-lib`的链接库和头文件，输出到`/sdk/mplayer/install`目录下面。

```bash
$ ./configure \
--host=arm-ca9-linux-gnueabihf \
--enable-shared \
--disable-python \
--prefix=/sdk/mplayer/install \
CC=arm-ca9-linux-gnueabihf-gcc

$ make && make install
```

#### 3. 交叉编译`Mplayer`源码

```bash
$ ./configure \
--prefix=/sdk/mplayer/install \
--disable-mencoder \
--disable-live \
--disable-mp3lib \
--disable-win32dll \
--disable-dvb \
--disable-dvdread \
--disable-dvdnav \
--disable-dvdread-internal \
--disable-tv \
--disable-ivtv \
--enable-fbdev \
--disable-sdl \
--cc=arm-ca9-linux-gnueabihf-gcc \
--host-cc=gcc \
--target=arm-linux \
--enable-mad \
--enable-alsa \
--enable-cross-compile \
--enable-armv5te \
--extra-cflags="-I/sdk/mplayer/install/include" \
--extra-ldflags="-L/sdk/mplayer/install/lib"

$ make && make install
```

### 三、Mplayer移植相关问题

在编译好相关源码之后，我们可以将生成的可执行文件和动态链接库等文件部署到开发板上去：

```bash
$ scp -r ./install/bin/mplayer root@10.10.110.XXX:/bin/
$ scp -r ./install/lib/ root@10.10.110.XXX:/
```

#### 1. 指定输出的`fbdev`设备

根据需求，设置`-vo`参数中`fbdev`默认打开的`framebuffer`设备：

```cpp
// /path/to/mplayer/libvo/vo_fbdev.c

static int fb_preinit(int reset)
{
    ...
    if (!fb_dev_name && !(fb_dev_name = getenv("FRAMEBUFFER")))
        fb_dev_name = strdup("/dev/fb1");
    ...
}
```

#### 2. Cannot initialize video driver问题

执行如下测试命令：

```bash
$ mplayer -vo fbdev ./media/movie.mp4
```

却得到如下日志：

```text
VDec: vo config request - 640 x 368 (preferred colorspace: Planar YV12)
VDec: using Planar YV12 as output csp (no 0)
VO: [fbdev] 640x360 => 640x360 BGRA  [zoom]
visual: 0 not yet supported
FATAL: Cannot initialize video driver.

FATAL: Could not initialize video filters (-vf) or video output (-vo).
```

后来打印出`fbdev`设备的`fb_var_screeninfo`参数，如下：

```text
Variable screen info:
        xres:1920
        yres:1080
        xres_virtual:1920
        yres_virtual:1080
        yoffset:0
        xoffset:0
        bits_per_pixel:32
        grayscale:0
        red: offset:16, length:  8, msb_right:  0
        green: offset: 8, length:  8, msb_right:  0
        blue: offset: 0, length:  8, msb_right:  0
        transp: offset:24, length:  4, msb_right:  0
        nonstd:0
        activate:0
        height:-1
        width:-1
        accel_flags:0x0
        pixclock:148500
        left_margin:148
        right_margin: 88
        upper_margin:36
        lower_margin:4
        hsync_len:44
        vsync_len:5
        sync:0
        vmode:0
```

通常来讲，`bits_per_pixel`为32的设备（ARGB8888），其透明度`transp`的位长应该是8。基于此，修改`vo_fbdev.c`文件如下：

```cpp
// /path/to/mplayer/libvo/vo_fbdev.c

static int fb_preinit(int reset)
{
    ...
    if (ioctl(fb_dev_fd, FBIOGET_VSCREENINFO, &fb_vinfo)) {
        mp_msg(MSGT_VO, MSGL_ERR, "Can't get VSCREENINFO: %s\n", strerror(errno));
        goto err_out_fd;
    }
+   fb_vinfo.transp.length = 8;
    ...
}

static int config(uint32_t width, uint32_t height, uint32_t d_width,
                  uint32_t d_height, uint32_t flags, char *title,
                  uint32_t format)
{
    ...
    switch (fb_bpp) {
+   case 28:
    case 32:
        draw_alpha_p = vo_draw_alpha_rgb32;
        break;
    ...
    default:
+       printf("%s --> %d, fb_bpp=%d error return\n", __func__, __LINE__, fb_bpp);
        return 1;
    }
}
```

#### 3. 其他调试工具等

`mplayer`源码中打印出`framebuffer`参数：

```cpp
static void printFixedInfo (struct fb_fix_screeninfo* finfo)
{
   printf ("Fixed screen info:\n"
                        "\tid: %s\n"
                        "\tsmem_start:0x%lx\n"
                        "\tsmem_len:%d\n"
                        "\ttype:%d\n"
                        "\ttype_aux:%d\n"
                        "\tvisual:%d\n"
                        "\txpanstep:%d\n"
                        "\typanstep:%d\n"
                        "\tywrapstep:%d\n"
                        "\tline_length: %d\n"
                        "\tmmio_start:0x%lx\n"
                        "\tmmio_len:%d\n"
                        "\taccel:%d\n"
           "\n",
           finfo->id, finfo->smem_start, finfo->smem_len, finfo->type,
           finfo->type_aux, finfo->visual, finfo->xpanstep, finfo->ypanstep,
           finfo->ywrapstep, finfo->line_length, finfo->mmio_start,
           finfo->mmio_len, finfo->accel);
}

static void printVariableInfo (struct fb_var_screeninfo* vinfo)
{
   printf ("Variable screen info:\n"
                        "\txres:%d\n"
                        "\tyres:%d\n"
                        "\txres_virtual:%d\n"
                        "\tyres_virtual:%d\n"
                        "\tyoffset:%d\n"
                        "\txoffset:%d\n"
                        "\tbits_per_pixel:%d\n"
                        "\tgrayscale:%d\n"
                        "\tred: offset:%2d, length: %2d, msb_right: %2d\n"
                        "\tgreen: offset:%2d, length: %2d, msb_right: %2d\n"
                        "\tblue: offset:%2d, length: %2d, msb_right: %2d\n"
                        "\ttransp: offset:%2d, length: %2d, msb_right: %2d\n"
                        "\tnonstd:%d\n"
                        "\tactivate:%d\n"
                        "\theight:%d\n"
                        "\twidth:%d\n"
                        "\taccel_flags:0x%x\n"
                        "\tpixclock:%d\n"
                        "\tleft_margin:%d\n"
                        "\tright_margin: %d\n"
                        "\tupper_margin:%d\n"
                        "\tlower_margin:%d\n"
                        "\thsync_len:%d\n"
                        "\tvsync_len:%d\n"
                        "\tsync:%d\n"
                       "\tvmode:%d\n"
           "\n",
           vinfo->xres, vinfo->yres, vinfo->xres_virtual, vinfo->yres_virtual,
           vinfo->xoffset, vinfo->yoffset, vinfo->bits_per_pixel,
           vinfo->grayscale, vinfo->red.offset, vinfo->red.length,
           vinfo->red.msb_right,vinfo->green.offset, vinfo->green.length,
           vinfo->green.msb_right, vinfo->blue.offset, vinfo->blue.length,
           vinfo->blue.msb_right, vinfo->transp.offset, vinfo->transp.length,
           vinfo->transp.msb_right, vinfo->nonstd, vinfo->activate,
           vinfo->height, vinfo->width, vinfo->accel_flags, vinfo->pixclock,
           vinfo->left_margin, vinfo->right_margin, vinfo->upper_margin,
           vinfo->lower_margin, vinfo->hsync_len, vinfo->vsync_len,
           vinfo->sync, vinfo->vmode);
}
```

查看`framebuffer`设备属性值：

```bash
$ fbset

mode "1920x1080-3"
        # D: 6.734 MHz, H: 3.061 kHz, V: 2.721 Hz
        geometry 1920 1080 1920 1080 16
        timings 148500 148 88 36 4 44 5
        accel false
        rgba 0/0,0/0,0/0,0/0
endmode

$ cat /sys/class/graphics/fb0/*
16
29:0
U:1920x1080p-2
flcd
0,0
0
0
3840
cat: read error: Is a directory
MAJOR=29
MINOR=0
DEVNAME=fb0
1920,1080
```

将图片数据写入到设备，测试`framebuffer`能否正常工作：

```bash
$ convert -resize 1280x720 -depth 8 ./input.png bgra:./output.bitmap
$ cat ./output.bitmap > /dev/fb0
```

媒体资源：

<video id="video" controls="" preload="none">
    <source id="mp4" src="https://www.runoob.com/try/demo_source/movie.mp4" type="video/mp4">
</video>
相关参考：

[MPlayer移植-迅为IMX6Q开发板][mplayer-porting]

[framebuffer的入门介绍-实现程序分析][framebuffer-introduction]

[把图片直接写入Framebuffer][write-picture-to-framebuffer]



[mplayer-website]: http://www.mplayerhq.hu/
[libmad-website]: https://www.underbit.com/products/mad/
[alsa-website]: http://www.alsa-project.org
[mplayer-porting]: https://zhuanlan.zhihu.com/p/149373847
[framebuffer-introduction]: https://blog.csdn.net/liuzijiang1123/article/details/46972723
[write-picture-to-framebuffer]: https://blog.yangl1996.com/post/ba-tu-pian-zhi-jie-xie-ru-framebuffer/
