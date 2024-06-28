---
layout: post
title:  "串行总线之I2C"
date:   2018-04-24 13:54:06 +0800
categories: notes
description: "嵌入式串行总线设备之I2C"
author: zburid
tags:   嵌入式 总线 I2C
typora-root-url: ..
show:   true
---

## 一、简介

`I2C`（`Inter-Integrated Circuit`）是一种由`Philips`设计的串行接口总线标准，使用多主从结构，详情参照官方资料：[UM10204](https://www.nxp.com/docs/en/user-guide/UM10204.pdf)

### 1、特点

`I2C`采用两条双向开漏电路：`串行数据 SDA` 和`串行时钟 SCL`，每根线上需要连接上拉电阻（约`4.7K`）到`VDD`。当总线空闲时，两根线都是高电平。

![I2C总线连接方法 From wikipedia][I2C_diagram]

`I2C`总线使用了一个`7bit`长度的地址位，但保留了`16`个地址，所以在一个总线系统中最多可以挂载`112`个通信节点。如果总线干扰严重，可以在两条线上增加一个`400PF`的滤波电容，增加电容的同时也会限制挂载节点的个数。

常见`I2C`总线依传输速率不同而分为不同的模式：*低速模式（10Kbit/s）*、*标准模式（100Kbit/s）*、*快速模式（400Kbit/s）*、*高速模式（3.4Mbit/s）*。

`I2C`总线上数据传输时，同一时刻只能有一个主机且`SCL`由主机控制。如果多个主机同时开始数据传输，可以通过冲突检测和仲裁防止数据破坏。

### 2、时序

#### 2.1、起始与结束位（START and STOP conditions）：

所有数据交互开始于`START`并以`STOP`为终结。`SCL`为高时`SDA`的下降沿表明一个`START`位，同样地`SCL`为高时`SDA`的上升沿表明一个`STOP`位。当总线监测到一个`START`位时表明总线进入`BUSY`模式，直到检测到一个`STOP`位才会认为总线可用。

![I2C 起始位结束位][i2c_start_stop_condition]


#### 2.2、字节流格式（Byte format）：

发送到`SDA`线上的每个数据都必须为`8bit`长，发送格式为`MSB`在前，而每次会话需要传输的字节数则没有限制，且每个数据都必须跟上一个由数据接收器的`ACK`应答位。如果从机不能立即做出应答或还没准备好发送或接收，从机可以拉低`SCL`时钟线直到准备好再释放`SCL`继续数据接收或发送。

![I2C 字节流格式][i2c_byte_stream_format]

#### 2.3、Acknowledge (ACK) and Not Acknowledge (NACK)：

在每个字节发送之后产生`ACK`，`ACK`可以让接收器通知发送器当前字节已成功接收，可以继续后续数据发送。`ACK`信号定义为：在`ACK`时钟期间发送器释放`SDA`总线，由接收器拉低`SDA`线。

![I2C ACK][i2c_acknowledge]

当在第九时钟周期内`SDA`仍然为高时，表明了一个`NACK`信号的产生。

![I2C NACK][i2c_not_acknowledge]

此时主机可以产生一个`STOP`来终止数据传输，或者重复一个`START`来开启一个新的数据传输。有`5`种情况导致`NACK`的产生：

    1. 当前总线没有符合地址的接收器设备来对发送器做出应答。
    2. 接收器正忙或没有准备好处理通信
    3. 在数据传输期间，接收器接收到未知的数据或命令
    4. 在数据传输期间，接收器不能再接收任何数据字节
    5. 主机接收器必须通知从机发送器数据传输的结束


#### 2.4、时钟同步（Clock synchronization）：

多主机总线系统中需要采用时钟同步。`I2C`接口采用线与（`wired-and`）的方式与`SCL`线连接来实现时钟同步，这意味着一个`SCL`线上的下降沿会重置主机的`LOW`电平计数器，直到最后一个上升沿的到来，`SCL`才会被拉高，而整个时钟周期就是最长的那个时钟周期。

![I2C 时钟同步][i2c_clock_sync]

#### 2.5、总线仲裁（Arbitration）：

多主机总线系统中需要采用总线仲裁。当总线空闲时主机开始发起一个数据传输，多个主机的总线里可能会出现多个主机在最小保持时间内同时产生`START`信号，此时需要总线仲裁哪个主机可以完成数据传输。

在每个位期间，当`SCL`为高电平时，每个主机都会检查`SDA`电平是否与它发送的电平相匹配。如果某个主机第一次尝试发送高电平时却检测到`SDA`上仍为低电平，则该主机自动识别为仲裁失败并关闭其`SDA`输出，在此期间无信息丢失。

失去仲裁的主机可以继续发出时钟信号直到该传输字节结束，当其需要发送时必须要等到总线空闲。如果该主机还有包含有从机接收功能，则必须切换到从机模式。

![I2C 总线仲裁][i2c_bus_arbitration]

如果仲裁过程中，某个主机发送一个重复`START`或`STOP`信号而其他主机仍在发送数据，会造成一种未定义的状态：

    1. 主机1发送一个重复START信号而主机2在发送一个数据bit
    2. 主机1发送一个重复STOP信号而主机2在发送一个数据bit
    3. 主机1发送一个重复START信号而主机2在发送一个重复STOP信号

#### 2.6、时钟拉伸与从机地址（Clock stretching & Slave address）：

如果从机不能立即做出应答或还没准备好发送或接收，从机可以拉低`SCL`时钟线直到准备好再释放`SCL`继续数据接收或发送。不过大多数从机并不具有该功能。

常用从机地址位长度为`7bit`，也可以支持`10bit`长度，不过较为少用。主机发送从机地址时也是按照`MSB`开始，第八位设置为读写位，其中读模式为`1`，写模式为`0`。

![I2C 从机地址][i2c_slave_address]


需要注意的是，有8个总线地址保留为特殊用处（X = 任意值; 1 = HIGH; 0 = LOW）：

| Slave address | R/W bit | 描述                                     |
| ------------- | ------- | ---------------------------------------- |
| 0000 000      | 0       | 通用呼叫地址（用于多种功能包括软件复位） |
| 0000 000      | 1       | `START` 字节                             |
| 0000 001      | X       | `CBUS` 地址                              |
| 0000 010      | X       | 保留                                     |
| 0000 011      | X       | 保留                                     |
| 0000 1XX      | X       | 高速模式                                 |
| 1111 1XX      | 1       | 设备`ID`                                 |
| 1111 0XX      | X       | `10bit`从机地址                          |

#### 2.7、常用数据传输格式

* 主发从收：主机发送器发送数据到从机接收器，数据传输方向不变，从机对接收到的每个字节响应`ACK`

![I2C 主发从收][i2c_master_send_slave_recv]

* 主收从发：主机在发送完从机地址后并获得了从机`ACK`响应，主机变为接收器从机变为发送器，主机对接收到的每个字节响应`ACK`。当主机需要结束数据传输时，先发送`NACK`然后发送`STOP`

![I2C 主收从发][i2c_master_recv_slave_send]

* 综合格式：在改变数据传输方向期间，主机将重复发送`START`和从机地址，并改变`R/W`位。主机发送器在重复发送`START`之前需要发送`NACK`

![I2C 综合格式][i2c_master_slave_send_recv]

### 3、流程与问题

* 1、`SCL`一直由`Master`控制，`SDA`依照数据传送的方向，读数据时由`Slave`控制`SDA`，写数据时由`Master`控制`SDA`。当8位数据传送完毕之后，应答位或者否应答位的`SDA`控制权与数据位传送时相反。

* 2、开始位`Start`和停止位`Stop`，只能由`Master`来发出。

* 3、地址的8位传送完毕后，成功配置地址的`Slave`设备必须发送`ACK`。否则否则一定时间之后`Master`视为超时，将放弃数据传送，发送`Stop`。

* 4、当写数据的时候，`Master`每发送完8个数据位，`Slave`设备如果还有空间接受下一个字节应该回答`ACK`，`Slave`设备如果没有空间接受更多的字节应该回答`NACK`，`Master`当收到`NACK`或者一定时间之后没收到任何数据将视为超时，此时`Master`放弃数据传送，发送`Stop`。

* 5、当读数据的时候，`Slave`设备每发送完8个数据位，如果`Master`希望继续读下一个字节，`Master`应该回答`ACK`以提示`Slave`准备下一个数据，如果`Master`不希望读取更多字节，`Master`应该回答`NACK`以提示`Slave`设备准备接收`Stop`信号。

* 6、当`Master`速度过快`Slave`端来不及处理时，`Slave`设备可以拉低`SCL`不放（`SCL=0`将发生“线与”）以阻止`Master`发送更多的数据。此时`Master`将视情况减慢或结束数据传送。

* 7、在`I2C`主设备进行读写操作的过程中，主设备在开始信号后控制`SCL`产生8个时钟脉冲，然后拉低`SCL`信号为低电平，在这个时候，从设备输出应答信号，将`SDA`信号拉为低电平。如果这个时候主设备异常复位，`SCL`就会被释放为高电平。此时，如果从设备没有复位，就会继续`I2C`的应答，将`SDA`一直拉为低电平，直到`SCL`变为低电平，才会结束应答信号。而对于`I2C`主设备来说，复位后检测`SCL`和`SDA`信号，如果发现`SDA`信号为低电平，则会认为`I2C`总线被占用，会一直等待`SCL`和`SDA`信号变为高电平。这样，`I2C`主设备等待从设备释放`SDA`信号，而同时`I2C`从设备又在等待主设备将`SCL`信号拉低以释放应答信号，两者相互等待，`I2C`总线进人一种死锁状态。同样，当`I2C`进行读操作，`I2C`从设备应答后输出数据，如果在这个时刻`I2C`主设备异常复位而此时`I2C`从设备输出的数据位正好为0，也会导致`I2C`总线进入死锁状态。


## 二、例子

### 1、EEPROM读写方式

`24C02`型号的`EEPROM`的数据读写方式如下：

![24C02 写字节][i2c_eeprom_byte_write]

![24C02 写页][i2c_eeprom_page_write]

对于数据写操作，主机为发送器从机为接收器。写入数据时需要指明需要写入数据的地址，地址通常为2个字节。

![24C02 读当前地址数据][i2c_eeprom_current_address_read]

![24C02 随机读取数据][i2c_eeprom_random_read]

![24C02 序列读取][i2c_eeprom_sequential_read]

对于数据读取操作，如果采用随机读取模式，需要采用常用的综合模式：发送一次写入操作写入需要随机读取的地址，然后再重发一次读取操作；序列读取或当前位置读取操作时，读取的数据地址由最后一次写入操作的位置或随机读取操作决定的。

### 2、ADC读写方式

![ADC 写时序][i2c_adc_write]

![ADC 读时序][i2c_adc_read]



[I2C_diagram]: /images/I2C.svg
[i2c_start_stop_condition]: /images/i2c_start_stop_condition.png
[i2c_byte_stream_format]: /images/i2c_byte_stream_format.png
[i2c_acknowledge]: /images/i2c_acknowledge.png
[i2c_not_acknowledge]: /images/i2c_not_acknowledge.png
[i2c_clock_sync]: /images/i2c_clock_sync.png
[i2c_bus_arbitration]: /images/i2c_bus_arbitration.png
[i2c_slave_address]: /images/i2c_slave_address.png
[i2c_master_send_slave_recv]: /images/i2c_master_send_slave_recv.png
[i2c_master_recv_slave_send]: /images/i2c_master_recv_slave_send.png
[i2c_master_slave_send_recv]: /images/i2c_master_slave_send_recv.png
[i2c_eeprom_byte_write]: /images/i2c_eeprom_byte_write.png
[i2c_eeprom_current_address_read]: /images/i2c_eeprom_current_address_read.png
[i2c_eeprom_page_write]: /images/i2c_eeprom_page_write.png
[i2c_eeprom_random_read]: /images/i2c_eeprom_random_read.png
[i2c_eeprom_sequential_read]: /images/i2c_eeprom_sequential_read.png
[i2c_adc_read]: /images/i2c_adc_read.png
[i2c_adc_write]: /images/i2c_adc_write.png