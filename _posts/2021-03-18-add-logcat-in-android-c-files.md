---
layout: post
title:  "Android C代码中添加日志打印"
date:   2021-03-18 15:32:31 +0800
categories: notes
description: "在Android C代码中添加logcat日志打印"
author: zburid
tags:   Android C logcat
typora-root-url: ..
show:   true
---

### 1. Android.bp

```diff
diff --git a/android_build/external/tinyalsa/Android.bp b/android_build/external/tinyalsa/Android.bp
index 090d91c0f8..5160936000 100644
--- a/android_build/external/tinyalsa/Android.bp
+++ b/android_build/external/tinyalsa/Android.bp
@@ -9,10 +9,15 @@ cc_library {
         "mixer.c",
         "pcm.c",
     ],
-    cflags: ["-Werror", "-Wno-macro-redefined"],
+    cflags: ["-Werror", "-Wno-macro-redefined", "-llog"],
     export_include_dirs: ["include"],
     local_include_dirs: ["include"],

+    shared_libs: [
+        "liblog",
+        "libutils",
+    ],
+
     target: {
         darwin: {
             enabled: false,
```


### 2. pcm.c

```diff
diff --git a/android_build/external/tinyalsa/pcm.c b/android_build/external/tinyalsa/pcm.c
index d69d79b25b..1de0177563 100644
--- a/android_build/external/tinyalsa/pcm.c
+++ b/android_build/external/tinyalsa/pcm.c
@@ -49,6 +49,10 @@

 #include <tinyalsa/asoundlib.h>

+#include <android/log.h>
+
+#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, "alsa_pcm", __VA_ARGS__)
+
 #define PARAM_MAX SNDRV_PCM_HW_PARAM_LAST_INTERVAL
 // This is from bionic/libc/kernel/uapi/sound/asound.h
 // But compiler uses this file firstly: prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.15-4.8/sysroot/usr/include/sound/asound.h
@@ -922,6 +926,8 @@ struct pcm *pcm_open(unsigned int card, unsigned int device,

     pcm->flags = flags;
     pcm->fd = open(fn, O_RDWR|O_NONBLOCK);
+       LOGW("%s: %s open with flags 0x%X and channel %d / rate %d / format %d / period_size %d / period_count %d / start_threshold %d / stop_threshold %d / silence_threshold %d / silence_size %d / avail_min %d and fd=0x%X\n",
+                __func__, fn, flags, config->channels, config->rate, config->format, config->period_size, config->period_count, config->start_threshold, config->stop_threshold, config->silence_threshold, config->silence_size, config->avail_min, pcm->fd);
     if (pcm->fd < 0) {
         oops(pcm, errno, "cannot open device '%s'", fn);
         return pcm;

```