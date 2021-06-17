---
layout: post
title:  "BAT批处理脚本记录"
date:   2020-12-22 13:48:24 +0800
categories: notes
description: "BAT批处理脚本常用功能的记录"
author: zburid
tags:   BAT Windows CMD
typora-root-url: ..
show:   true
---

### 1. 判断参数是否为数字，如果不是数字则执行XXX

```cmd
echo %3%|findstr "[^0-9]">nul && echo IAP MAX size should be number! && goto USAGE
```

### 2. 判断数字是否为4的倍数

```cmd
set /a tmpval=%3%/4*4
if %tmpval% neq %3% (
	echo IAP MAX size %3% is not a multiple of 4
	goto USAGE
)
```

### 3. 判断文件是否存在

```cmd
if not exist %pad% (
	echo %pad% is not exist! Please make sure pad file(0xff, 0xff, 0xff, 0xff)!
	goto USAGE
)
```

### 4. 获取某个文件路径中的目录、文件名

```cmd
for /f "delims=" %%i in ('dir /b "%0%"') do (
	if not defined pad (set pad=%%~dpi\pad.bin)
)
for /f "delims=" %%j in ('dir /b "%2%"') do (
	if not defined mcuname (set mcuname=%%~nj%%~xj)
)
```

### 5. 生成MD5并只取MD5的字符串

```cmd
for /f "skip=1 delims=" %%b in ('certutil -hashfile "%2%" MD5') do (
	if not defined mcuhash (set mcuhash=%%b)
)
```

