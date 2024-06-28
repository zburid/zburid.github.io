---
layout: post
title:  "Android自动化压力测试与日志获取"
date:   2021-05-20 16:20:39 +0800
categories: notes
description: "Android自动化压力测试与日志获取相关记录"
author: zburid
tags:   Android monkey adb 测试 日志
typora-root-url: ..
show:   true
mermaid: true
---

### 一、`ADB`工具

#### 1、[简介][adb_user_guide]

`ADB`全称为`Android Debug Bridge`，是一种功能多样的命令行工具，可让您与设备进行通信。`ADB`命令可用于执行各种设备操作（例如安装和调试应用），并提供对`Unix shell`（可用来在设备上运行各种命令）的访问权限。它是一种`Client`-`Server`程序，包括以下三个组件：

	Client：用于发送命令。客户端在开发计算机上运行。可以通过发出 adb 命令从命令行终端调用客户端。
	守护进程 (adbd)：用于在设备上运行命令。守护程序在每个设备上作为后台进程运行。
	Server：用于管理客户端与守护程序之间的通信。服务器在开发机器上作为后台进程运行。

#### 2、安装

从官网下载[ADB Driver Installer][ADB_Driver_Installer_Download_URL]

![adb driver installer interface][adb_driver_installer_interface]

用USB数据线连接PC与设备，即可选择设备并安装ADB驱动程序。

安装完驱动后还需要安装`adb`工具，选择下载[`platform-tools`][platform-tools-url]，并将其路径添加到系统`PATH`中去。该工具也可以通过安装`Android Studio`来获取。

#### 3、常见用法

查看`ADB`所支持的命令：

```shell
$ adb --help
```

查询设备：

```shell
$ adb devices -l
List of devices attached
emulator-5556 device product:sdk_google_phone_x86_64 model:Android_SDK_built_for_x86_64 device:generic_x86_64
emulator-5554 device product:sdk_google_phone_x86 model:Android_SDK_built_for_x86 device:generic_x86
0a388e93      device usb:1-1 product:razor model:Nexus_7 device:flo

$ adb [-d | -e | -s serial_number] command
```

安装应用：

```shell
$ adb install path_to_apk
```

文件复制：

```shell
$ adb pull remote local
$ adb push local remote
```

重置`ADB`：

```shell
$ adb kill-server
```

`Shell`命令：

```shell
$ adb [-d |-e | -s serial_number] shell shell_command
```

`Shell`常见命令：

```shell
$ adb shell am command          # 调用 Activity 管理器（am）
$ adb shell pm command          # 调用软件包管理器 (pm)
$ adb shell dpm command         # 调用设备策略管理器 (dpm)
$ adb shell screencap filename  # 屏幕截图
$ adb shell serverce list       # 查看系统服务
```

`dumpsys`命令：

```shell
$ adb shell dumpsys meminfo         # 内存信息
$ adb shell dumpsys cpuinfo         # CPU信息
$ adb shell dumpsys connectivity    # 网络连接
$ adb shell dumpsys location        # 位置信息
$ adb shell dumpsys activity [-a] [-c] [-p] [-h] [subcmd]   # 查询 activity 信息
$ adb shell dumpsys package [-h] [-f] [--checkin] [cmd]     # 查询包信息
```




### 二、`Monkey`工具

#### 1、简介

`Monkey`是`Google`提供的一个用于稳定性与压力测试的命令行工具。通过向系统发送伪随机的用户事件流（如按键输入、触摸屏输入、滑动Trackball、手势输入等操作），来对设备上的程序进行测试，检测程序长时间的稳定性，多久的时间会发生异常。

`Monkey`工具使用`Java`语言写成，存在于`Android`系统中：

```shell
$ ls -a -l /system/framework/monkey.jar
$ ls -a -l /system/bin/monkey
```

#### 2、工作原理

在`Monkey`运行的时候，它会生成事件，并把它们发给系统。同时，`Monkey`还对测试中的系统进行监测，对下列三种情况进行特殊处理：

(1) 如果限定了`Monkey`运行在一个或几个特定的包上，那么它会监测试图转到其它包的操作，并对其进行阻止；

(2) 如果应用程序崩溃或接收到任何失控异常，`Monkey`将停止并报错；

(3) 如果应用程序产生了应用程序不响应`ANR`(application not responding)的错误，`Monkey`将会停止并报错；

按照选定的不同级别的反馈信息，在`Monkey`中还可以看到其执行过程报告和生成的事件。

#### 3、命令参数

```shell
$ adb shell monkey --help
usage: monkey [-p ALLOWED_PACKAGE [-p ALLOWED_PACKAGE] ...]
              [-c MAIN_CATEGORY [-c MAIN_CATEGORY] ...]
              [--ignore-crashes] [--ignore-timeouts]
              [--ignore-security-exceptions]
              [--monitor-native-crashes] [--ignore-native-crashes]
              [--kill-process-after-error] [--hprof]
              [--match-description TEXT]
              [--pct-touch PERCENT] [--pct-motion PERCENT]
              [--pct-trackball PERCENT] [--pct-syskeys PERCENT]
              [--pct-nav PERCENT] [--pct-majornav PERCENT]
              [--pct-appswitch PERCENT] [--pct-flip PERCENT]
              [--pct-anyevent PERCENT] [--pct-pinchzoom PERCENT]
              [--pct-permission PERCENT]
              [--pkg-blacklist-file PACKAGE_BLACKLIST_FILE]
              [--pkg-whitelist-file PACKAGE_WHITELIST_FILE]
              [--wait-dbg] [--dbg-no-events]
              [--setup scriptfile] [-f scriptfile [-f scriptfile] ...]
              [--port port]
              [-s SEED] [-v [-v] ...]
              [--throttle MILLISEC] [--randomize-throttle]
              [--profile-wait MILLISEC]
              [--device-sleep-time MILLISEC]
              [--randomize-script]
              [--script-log]
              [--bugreport]
              [--periodic-bugreport]
              [--permission-target-system]
              COUNT
```

![monkey-common-params-1][monkey-common-params-1]

```shell
$ adb shell monkey -p com.xxx.myapp --throttle 100 --ignore-crashes --ignore-timeouts --ignore-security-exceptions --ignore-native-crashes --monitor-native-crashes -v -v -v 1000000
```

**-p** 指定包名
 **--throttle 100** MILLISEC事件之间插入的固定延迟。通过这个选项可以减缓`Monkey`的执行速度。如果不指定，`Monkey`将尽可能快的产生并执行事件
**--ignore-crashes** 作用：通常，应用发生崩溃或异常时`Monkey`会停止运行。如果设置此项，`Monkey`将继续发送事件给系统，直到事件计数完成。
 **--ignore-timeouts** 作用：通常，应用程序发生任何超时错误（如“Application Not responding”对话框）`Monkey`将停止运行，设置此项，`Monkey`将继续发送事件给系统，直到事件计数完成。
 **--ignore-security-exception** 作用：通常，当程序发生许可错误（例如启动一些需要许可的Activity）导致的异常时，`Monkey`将停止运行。设置此项，`Monkey`将继续发送事件给系统，直到事件计数完成。
 **--ignore-native-crashes** 忽略本地代码导致的崩溃。设置忽略后，`Monkey`将执行完所有的事件，不会因此停止
**--monitor-native-crashes** 监视崩溃时的本地代码
 **-v** 每个-v都将增加反馈信息的级别。共3个级别，因此，-v -v -v可以提供最详细的设置信息。
**1000000** 这里是指点击的次数

![monkey-common-params-2](/images/monkey-common-params-2.png)

![monkey-common-params-3](/images/monkey-common-params-3.png)



### 三、日志获取

```shell
# 获取软件包名
adb shell pm list packages

# 保存logcat日志到文件并清空日志缓存
adb shell logcat -d > logcat-$(date +%Y-%m-%d_%H-%M-%S).log && adb shell logcat -c

# 开启monkey测试并保存到日志文件中去
adb shell monkey -p com.xxxx.project123.xxxx --pct-syskeys 0 --throttle 500 -v 500000 | tee monkey-$(date +%Y-%m-%d_%H-%M-%S).log

# 获取ANR日志
adb pull /data/anr/traces.txt D:\workspace\xxxx\

# 获取安卓系统崩溃日志
adb pull /data/tombstones D:\workspace\xxxx\
```



参考文档：

[Monkey测试][monkey_test_article_url]

[Android自动化压力测试之Monkey Test （三）](https://www.cnblogs.com/Lam7/p/5459153.html)





[adb_user_guide]: https://developer.android.google.cn/studio/command-line/adb
[ADB_Driver_Installer_Download_URL]: https://dl.adbdriver.com/upload/ADBDriverInstaller.exe
[platform-tools-url]: https://developer.android.google.cn/studio/releases/platform-tools
[monkey_test_article_url]: https://www.jianshu.com/p/f332c1b01db7
[adb_driver_installer_interface]: /images/adb_driver_installer_interface.png
[monkey-common-params-1]: /images/monkey-common-params-1.jpg
[monkey-common-params-2]: /images/monkey-common-params-2.png
[monkey-common-params-3]: /images/monkey-common-params-3.png

