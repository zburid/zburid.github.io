---
layout: post
title:  "双TP双屏异显触控实现"
date:   2020-11-26 13:14:03 +0800
categories: notes
description: "Android4.4下双TP双屏异显触控实现记录"
author: zburid
tags:   TP Android
typora-root-url: ..
show:   true
---

#### 1、添加多个触摸屏驱动

在内核中使能多个TP的驱动，具体情况略。

#### 2、修改Framework中转发TP事件的部分

根据TP的名称判断需要将当前的TP事件转发到哪个`displayId`上去。如下程序检测是否为`Atmel`的触摸屏，并将其`displayId`强置为第二个屏幕。

```diff
// frameworks/base/services/input/InputReader.cpp
void TouchInputMapper::dispatchMotion(nsecs_t when, uint32_t policyFlags, uint32_t source,
    ...
+    int displayId = mViewport.displayId;
+    if(strcmp(getDeviceName().string(),"atmel_mxt_ts")==0) {
+        displayId = 1;
+    }
+    ALOGE("getDeviceId()=%d,getDeviceName=%s,displayId=%d",getDeviceId(),getDeviceName().string(),displayId);

    NotifyMotionArgs args(when, getDeviceId(), source, policyFlags,
            action, flags, metaState, buttonState, edgeFlags,
            displayId, pointerCount, pointerProperties, pointerCoords,
            xPrecision, yPrecision, downTime);
    getListener()->notifyMotion(&args);
```

缺点：同一时间只能处理一个TP的数据，多个TP同时使用时会出现某个TP占用时间资源的情况。
