---
layout: post
title:  "Atmel触摸按键功能支持"
date:   2021-01-18 08:50:32 +0800
categories: notes
description: "Atmel触摸屏按键功能和反馈音功能添加记录"
author: zburid
tags:   Android Atmel TP 按键
typora-root-url: ..
show:   true
---

需要在Atmel触摸屏上实现4个触摸按键，分别是：BACK、HOME、Favorite、HDMI这4个。其中BACK与HOME需要关联到Android系统上的返回与HOME功能。

### 一、TP驱动支持

```diff
diff --git a/kernel/drivers/input/touchscreen/atmel_mxt_ts.c b/kernel/drivers/input/touchscreen/atmel_mxt_ts.c
index 9c5e67c3e2..c9a87c553d 100755
--- a/kernel/drivers/input/touchscreen/atmel_mxt_ts.c
+++ b/kernel/drivers/input/touchscreen/atmel_mxt_ts.c
@@ -1052,12 +1052,18 @@ static void mxt_proc_t15_messages(struct mxt_data *data, u8 *msg)
                        __set_bit(key, &data->t15_keystatus);
                        input_event(input_dev, EV_KEY,
                                    data->pdata->t15_keymap[key], 1);
+                       if (key == 0) {
+                               input_event(input_dev, EV_KEY,
+                                   data->pdata->t15_keymap[4], 1);
+                       } else if (key == 2) {
+                               input_event(input_dev, EV_KEY,
+                                   data->pdata->t15_keymap[5], 1);
+                       }
                        sync = true;
                } else if (curr_state && !new_state) {
                        dev_dbg(dev, "T15 key release: %u\n", key);
                        __clear_bit(key, &data->t15_keystatus);
                        input_event(input_dev, EV_KEY,
                                    data->pdata->t15_keymap[key], 0);
+                       if (key == 0) {
+                               input_event(input_dev, EV_KEY,
+                                   data->pdata->t15_keymap[4], 0);
+                       } else if (key == 2) {
+                               input_event(input_dev, EV_KEY,
+                                   data->pdata->t15_keymap[5], 0);
+                       }
                        sync = true;
                }
        }
@@ -3218,7 +3224,7 @@ static struct mxt_platform_data *mxt_parse_dt(struct i2c_client *client)
        if (!keymap)
                return NULL;
        for(key_i=0;key_i<10;key_i++)
+               keymap[key_i] = key_i+520; //生成520到529这10个键值
        pdata->t15_keymap = keymap;
        //for(key_i=0;key_i<10;key_i++)
        //      keymap[key_i]=key_i;
```

需要注意到，为了向上层传递HOME与BACK键值，在监测到520和522按键时，同时还向上传递了524和525键值。

```diff
diff --git a/kernel/include/linux/input.h b/kernel/include/linux/input.h
index a83060c928..d409081e84 100755
--- a/kernel/include/linux/input.h
+++ b/kernel/include/linux/input.h
@@ -294,8 +294,8 @@

 #define KEY_MICMUTE            248     /* Mute / unmute the microphone */

+#define KEY_XXXX_XXXXX_HOME    520     /* HOME Key */
+#define KEY_XXXX_XXXXX_CUSTOM  521     /* Custom favorite page access Key */
+#define KEY_XXXX_XXXXX_BACK    522     /* BACK Key */
+#define KEY_XXXX_XXXXX_HDMI    523     /* HDMI switch Key */
+
 /**
  * struct input_value - input value representation
  * @type: type of value (EV_KEY, EV_ABS, etc)
```

### 二、Framework支持

首先修改`Generic.kl`（key layout）文件，该文件是一个映射文件，是标准linux与anroid的键值映射文件。

```diff
diff --git a/frameworks/base/data/keyboards/Generic.kl b/frameworks/base/data/keyboards/Generic.kl
index a1e7f89d9a..1b4380db70 100755
--- a/frameworks/base/data/keyboards/Generic.kl
+++ b/frameworks/base/data/keyboards/Generic.kl

+key 520   XXXX_XXXXX_HOME
+key 521   XXXX_XXXXX_CUSTOM
+key 522   XXXX_XXXXX_BACK
+key 523   XXXX_XXXXX_HDMI
+key 524   HOME
+key 525   BACK
+
 # Keys defined by HID usages
 key usage 0x0c006F BRIGHTNESS_UP
 key usage 0x0c0070 BRIGHTNESS_DOWN
```

除了`kl`文件外，还需要修改`KeyEvent.java`、`attrs.xml`、`keycodes.h`、`KeycodeLabels.h`、`Input.cpp`等文件：

```diff
diff --git a/frameworks/base/core/java/android/view/KeyEvent.java b/frameworks/base/core/java/android/view/KeyEvent.java
index 32add7ab0c..faa0d0c6af 100755
--- a/frameworks/base/core/java/android/view/KeyEvent.java
+++ b/frameworks/base/core/java/android/view/KeyEvent.java
@@ -642,7 +642,12 @@ public class KeyEvent extends InputEvent implements Parcelable {
-    private static final int LAST_KEYCODE           = KEYCODE_MEDIA_AUDIO_TRACK;
+
+    public static final int KEYCODE_XXXX_XXXXX_HOME   = 520;
+    public static final int KEYCODE_XXXX_XXXXX_CUSTOM = 521;
+    public static final int KEYCODE_XXXX_XXXXX_BACK   = 522;
+    public static final int KEYCODE_XXXX_XXXXX_HDMI   = 523;
+    private static final int LAST_KEYCODE           = KEYCODE_XXXX_XXXXX_HDMI;

     // NOTE: If you add a new keycode here you must also add it to:
     //  isSystem()
@@ -897,6 +902,10 @@ public class KeyEvent extends InputEvent implements Parcelable {
+        names.append(KEYCODE_XXXX_XXXXX_HOME, "KEYCOE_XXXX_XXXXX_HOME");
+        names.append(KEYCODE_XXXX_XXXXX_CUSTOM, "KEYCOE_XXXX_XXXXX_CUSTOM");
+        names.append(KEYCODE_XXXX_XXXXX_BACK, "KEYCOE_XXXX_XXXXX_BACK");
+        names.append(KEYCODE_XXXX_XXXXX_HDMI, "KEYCOE_XXXX_XXXXX_HDMI");
     };

     // Symbolic names of all metakeys in bit order from least significant to most significant.
```

```diff
diff --git a/frameworks/base/core/res/res/values/attrs.xml b/frameworks/base/core/res/res/values/attrs.xml
index 831d697970..0d1e56c422 100755
--- a/frameworks/base/core/res/res/values/attrs.xml
+++ b/frameworks/base/core/res/res/values/attrs.xml
@@ -1577,6 +1577,10 @@
+        <enum name="KEYCODE_XXXX_XXXXX_HOME" value="520" />
+        <enum name="KEYCODE_XXXX_XXXXX_CUSTOM" value="521" />
+        <enum name="KEYCODE_XXXX_XXXXX_BACK" value="522" />
+        <enum name="KEYCODE_XXXX_XXXXX_HDMI" value="523" />
     </attr>

     <!-- ***************************************************************** -->
diff --git a/frameworks/native/include/android/keycodes.h b/frameworks/native/include/android/keycodes.h
index 0a7d75ba50..2126d88051 100755
--- a/frameworks/native/include/android/keycodes.h
+++ b/frameworks/native/include/android/keycodes.h
@@ -277,6 +277,11 @@ enum {
+    AKEYCODE_XXXX_XXXXX_HOME = 520,
+    AKEYCODE_XXXX_XXXXX_CUSTOM = 521,
+    AKEYCODE_XXXX_XXXXX_BACK = 522,
+    AKEYCODE_XXXX_XXXXX_HDMI = 523,
     // NOTE: If you add a new keycode here you must also add it to several other files.
     //       Refer to frameworks/base/core/java/android/view/KeyEvent.java for the full list.
 };
diff --git a/frameworks/native/include/input/KeycodeLabels.h b/frameworks/native/include/input/KeycodeLabels.h
index cc11311904..de391450d9 100755
--- a/frameworks/native/include/input/KeycodeLabels.h
+++ b/frameworks/native/include/input/KeycodeLabels.h
@@ -257,6 +257,10 @@ static const KeycodeLabel KEYCODES[] = {
+    { "XXXX_XXXXX_HOME", 520 },
+    { "XXXX_XXXXX_CUSTOM", 521 },
+    { "XXXX_XXXXX_BACK", 522 },
+    { "XXXX_XXXXX_HDMI", 523 },

     // NOTE: If you add a new keycode here you must also add it to several other files.
     //       Refer to frameworks/base/core/java/android/view/KeyEvent.java for the full list.
diff --git a/frameworks/native/libs/input/Input.cpp b/frameworks/native/libs/input/Input.cpp
index ebe5a3f9ea..91ff69a472 100755
--- a/frameworks/native/libs/input/Input.cpp
+++ b/frameworks/native/libs/input/Input.cpp
@@ -120,6 +120,10 @@ bool KeyEvent::isSystemKey(int32_t keyCode) {
+        case AKEYCODE_XXXX_XXXXX_HOME:
+        case AKEYCODE_XXXX_XXXXX_CUSTOM:
+        case AKEYCODE_XXXX_XXXXX_BACK:
+        case AKEYCODE_XXXX_XXXXX_HDMI:
             return true;
     }
```

如上修改基本上能够实现HOME与BACK的系统按键功能，满足APP监测到固定键值并由APP实现相关操作的功能。

### 三、添加按键反馈音

```diff
diff --git a/frameworks/base/policy/src/com/android/internal/policy/impl/PhoneWindowManager.java b/frameworks/base/policy/src/com/android/internal/policy/impl/PhoneWindowManager.java
index fd0ce63a04..273b98ac82 100755
--- a/frameworks/base/policy/src/com/android/internal/policy/impl/PhoneWindowManager.java
+++ b/frameworks/base/policy/src/com/android/internal/policy/impl/PhoneWindowManager.java
@@ -2127,6 +2127,10 @@ public class PhoneWindowManager implements WindowManagerPolicy {
                     + " canceled=" + canceled);
         }

+        if (down && keyCode >= 520 && keyCode <= 523) {
+            performVirtualKeyClickSound();
+        }
+
         // If we think we might have a volume down & power key chord on the way
         // but we're not sure, then tell the dispatcher to wait a little while and
         // try again later before dispatching.
@@ -4083,6 +4087,16 @@ public class PhoneWindowManager implements WindowManagerPolicy {
         }
     }

+    private void performVirtualKeyClickSound() {
+        AudioManager audioManager = (AudioManager)mContext.getSystemService(Context.AUDIO_SERVICE);
+        if (audioManager != null) {
+            Log.d(TAG, "interceptKeyTq  ssssssssssssssss performVirtualKeyClickSound ");
+            audioManager.playSoundEffect(AudioManager.FX_KEY_CLICK);
+        } else {
+            Log.w(TAG, "performVirtualKeyClickSound");
+        }
+    }
+
     /** {@inheritDoc} */
     @Override
     public int interceptKeyBeforeQueueing(KeyEvent event, int policyFlags, boolean isScreenOn) {
```



### 四、其他相关问题

#### 1、触摸按键在主APP后台时不能实现BACK和HOME功能

需要TP将BACK与HOME的事件直接映射到系统的BACK与HOME键值上。之前的方案是由APP检测到键值并由APP向系统发送返回与HOME事件，这样的话在APP退出到后台就不能实现按键事件的转发了。

#### 2、主APP应用重启后触摸按键失效

内核日志查看到驱动正常检测到触摸按键事件。经APP方面检查发现是Android无障碍服务没有正确应用导致的该问题。

参考文档：

[android 9.0 增加实体按键的按键声音，以及增加按键声音的开关](https://blog.csdn.net/wed110/article/details/106242708)

[android kl文件](https://www.cnblogs.com/linhaostudy/p/8857636.html)

