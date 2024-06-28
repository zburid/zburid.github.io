---
layout: post
title:  "MacOS如何科学上网"
date:   2021-03-08 10:14:42 +0800
categories: notes
description: "MacOS下使用工具ClashX科学上网"
author: zburid
tags:   MacOS ClashX VPN
typora-root-url: ..
show:   true
---

### 1、安装ClashX软件

[**ClashX**](https://github.com/yichengchen/clashX/releases/latest)

打开链接并选择最后的release版本下载安装程序

### 2、添加免费机场订阅地址

[**Free886**](https://free886.herokuapp.com/clash)

- Clash配置文件：https://free886.herokuapp.com/clash/config **一键导入**

- Clash proxy-provider(Shadowrocket添加订阅方式可用)：https://free886.herokuapp.com/clash/proxies

- 筛选代理类型(此种方式你只能自己维护配置文件)：https://free886.herokuapp.com/clash/proxies?type=ss,ssr,vmess

- 筛选国家(此种方式你只能自己维护配置文件)：https://free886.herokuapp.com/clash/proxies?type=ss,ssr,vmess&c=HK,TW,US

- 所有节点的Provider(不是都可以用)：https://free886.herokuapp.com/clash/proxies?type=all

- 抓取程序已开源：https://github.com/zu1k/proxypool



[**stgod**](https://hello.stgod.com/clash)

- Clash配置文件: https://hello.stgod.com/clash/config [一键导入](clash://install-config?url=https://hello.stgod.com/clash/config)

- 本地运行时Clash配置文件: http://127.0.0.1:12580/clash/localconfig [一键导入](clash://install-config?url=http://127.0.0.1:12580/clash/localconfig)

- Clash proxy-provider：https://hello.stgod.com/clash/proxies

- 筛选代理类型：https://hello.stgod.com/clash/proxies?type=ss,ssr,vmess

- 筛选国家：https://hello.stgod.com/clash/proxies?c=HK,TW,US&nc=JP (c为需要的国家，nc为不需要的国家)

- 筛选速度（十分不准确仅供参考）：https://hello.stgod.com/clash/proxies?speed=0 (默认开启，-1不显示，单个参数为大于该速度，两个参数选择区间)

- 所有节点的Provider(不是都可以用)：https://hello.stgod.com/clash/proxies?type=all

- 更新方法：
  - Clash for Windows: 更新配置文件即可
  - ClashX: Dashboard中，点击每个策略组右上角的刷新图标
  - ClashXPro: Config → Update External Sources
