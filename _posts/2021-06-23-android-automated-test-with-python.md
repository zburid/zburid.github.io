---
layout: post
title:  "使用Python自动化测试Android"
date:   2021-06-23 09:51:15 +0800
categories: notes
description: "使用Python进行Android自动化测试笔记"
author: zburid
tags:   Python Android 测试
typora-root-url: ..
show:   true
mermaid: true
---


### 一、功能需求

使用`Monkey`测试已经能够检测到`APP`中存在的各种问题了，但`Monkey`是“搞怪”随机操作，对于一些可能需要特定的操作流程、重复的操作才能暴露的问题，需要使用`Python`脚本来实现自动化测试。

采用`Python`脚本发送`adb`命令的方式，来模拟人为的点击、滑动、输入等操作。



### 二、功能实现

主要使用`os.system`实现`adb`命令的发送：

```python
>>> import os
>>> os.system("adb devices")
List of devices attached
0f10380e82964091        device

0
```



#### 1. 模拟点击

```python
def click(x, y):
    ''' 点击坐标为 (x, y) '''
    cmd = "adb shell input tap {px} {py}".format(
        px = x, py = y
    )
    os.system(cmd)
```

如何获取需要点击的位置的坐标呢？可以通过使能`TP`报点的方式先人工确认点击位置的坐标：

```shell
adb shell settings put system show_touches 1
adb shell settings put system pointer_location 1
```



#### 2. 模拟滑动

```python
def swipe(x1, y1, x2, y2):
    ''' 滑动范围为从 (x1, y1) 到 (x2, y2) '''
    cmd = "adb shell input swipe {start_x} {start_y} {end_x} {end_y}".format(
        start_x = x1, start_y = y1
        end_x = x2, end_y = y2
    )
    os.system(cmd)
```



#### 3. 输入字符串

```python
def input_string(s):
    ''' 模拟输入字符串 '''
    cmd = "adb shell input text {}".format(s)
    os.system(cmd)
```



#### 4. 控件布局

```python
def screen_xml():
    ''' 获取当前界面控件布局 '''
    os.system("adb shell uiautomator dump /data/local/tmp/ui.xml")
    os.system("adb pull /data/local/tmp/ui.xml")
```

在实际测试过程中，如果需要判断当前页面是否操作成功、页面是否跳转等，可以通过读取上述`xml`文件来判断当前页面的状态：

```python
def find_element(ele):
    screen_xml()
    with open("ui.xml", "r") as f:
        xml = f.read()
    if xml.find(ele) == -1:
        # Do something with element not found
        pass
    else:
        # Do something with element found
        pass
```



### 三、其他方案

上述方案只能实现一些简单重复性的自动化测试操作，如果需要想要实现复杂的可交互性质的测试方案，则需要采用第三方框架。常见的框架有`UiAutomator2`和`appium`。



#### 1. [UI Automator ][UI_Automator_website]

`UI Automator`是`Google`官方提供的一个`Android`自动化测试框架。该框架可以实现获取屏幕控件和相关操作的功能，十分强大。但是，该框架有两个主要的缺点：

1. 只支持`java`语言进行脚本开发
2. 测试脚本要打包成`jar`或者`apk`包上传到设备上才能运行，环境准备和搭建都比较繁琐

为此可以选择[`UiAutomator2`][uiautomator2_website]框架，该框架底层基于`Google`的`UI Automator`，可以获取屏幕上任意一个`APP`的任意一个控件属性，并对其进行任意操作，安装如下：

```shell
pip3 install --pre -U uiautomator2
```

测试连接环境：

```python
>>> import uiautomator2 as u2
>>> d = u2.connect()
>>> print(d.info)
>>> {'currentPackageName': 'com.google.android.car.kitchensink', 'displayHeight': 912, 'displayRotation': 0, 'displaySizeDpX': 1280, 'displaySizeDpY': 720, 'displayWidth': 1920, 'productName': 'mek_8q_car', 'sc
reenOn': True, 'sdkInt': 29, 'naturalOrientation': True}
```

其他方面参照网上例程进行功能编写即可。



#### 2. Appium

[`Appium`][appium_website]是一个开源工具，用于自动化`iOS`手机、`Android`手机和`Windows`桌面平台上的原生、移动`Web`和混合应用。`Appium`使用了系统自带的自动化测试框架，对于`Android4.3+`，也是采用了`Google`的`UiAutomator/UiAutomator2`。

安装如下：

```shell
pip install Appium-Python-Client
```

安装`Appium-desktop`：

`Appium-desktop`是`Appium`更为优化的图形界面和`Appium`相关的工具的组合，可以用来监听移动设备、设置选项、启动/停止服务器、查看日志等功能；可以使用`Inspector`来查看应用程序的元素，并进行基本的交互。

打开[链接🔗][appium_desktop_releases]，根据自己的平台选择相关安装包并安装即可。

![Appium_home][appium_home]

其他方面参照网上例程进行功能编写即可。



### 四、常用Python库

#### 1. built-in

* `os`模块主要用来操作文件、目录，与操作系统无关

* `sys`模块包括了一组非常实用的服务，内含很多函数方法和变量，用来处理`Python`运行时配置以及资源，从而可以与前当程序之外的系统环境交互

  比如`sys.argv`可以获得用户执行命令时的用户输入参数

* `random`模块可以用于获取随机数

* `time`模块可以用于处理与时间相关的功能

* `re`模块用于处理复杂文本的过滤功能

* `subprocess`模块允许我们启动一个新进程，并连接到它们的输入/输出/错误管道，从而获取返回值

* `tkinter`模块用于绘制`UI`界面



#### 2. unittest

`unittest`是`python`的单元测试框架，`unittest`单元测试提供了创建测试用例，测试套件以及批量执行的方案。可以使用该工具生成测试报告。



参考资料：

[基于python的android自动化测试脚本](https://blog.csdn.net/HappinessCat/article/details/84134284)

[使用 python 实现 Android Uiautomator 自动化测试脚本开发和实战](https://testerhome.com/articles/21317)

[python+appium+android实现自动化测试](https://www.cnblogs.com/weibgg/p/13660117.html)

[UIAutomator2](https://www.jianshu.com/p/e5ed2ddb3f27)

[unittest测试框架](https://blog.csdn.net/weixin_43688527/article/details/106723142)

[Appium Desktop 介绍及安装使用](https://blog.csdn.net/linlu_home/article/details/79172208)



[UI_Automator_website]: https://developer.android.google.cn/training/testing/ui-automator
[uiautomator2_website]: https://github.com/openatx/uiautomator2
[appium_website]: http://appium.io/
[appium_desktop_releases]: https://github.com/appium/appium-desktop/releases

[appium_home]: /images/appium_home.jpg
