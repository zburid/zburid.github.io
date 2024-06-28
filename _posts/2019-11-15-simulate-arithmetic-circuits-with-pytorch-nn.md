---
layout: post
title:  "使用神经网络模拟运算电路"
date:   2019-11-15 09:15:34 +0800
categories: notes
description: "使用神经网络模拟运算电路，采用Pytorch实现"
author: zburid
tags:   pytorch 神经网络 深度学习 运算电路
typora-root-url: ..
show:   true
---
### 一、简述
想要实现一个由神经网络来模拟的加法器（或乘法器或除法器）模型~~（看看概率模型如何实现逻辑运算😂）~~。

众所周知，实现一个简单的运算器时需要很多逻辑门（与或非），而每个逻辑门又由多个`CMOS`电路组成，如下就是一个`2bit`加法器的`CMOS`版图实现，包括进位输入和进位输出：

![2bit加法器][2bit_add_cmos_layout]

不考虑超前进位的话，只需要将如上版图复制`N`份，每份的进位首尾相连，就能实现一个简单的`N`位加法器了。

然而正如所看到的那样，电路是数字电路~~（就不考虑`CMOS`的导通特性了，扯太远了，也不会）~~，运算是按照逻辑进行的，这让我好奇运行着浮点数的神经网络模型，该如何模拟逻辑运算。

### 二、数据集生成

首先需要引入库：

```python
import numpy as np
import random

import torch
import torch.nn as nn
import torch.nn.functional as F
import torch.optim as optim

from torch.utils.data import Dataset
from torch.utils.data import DataLoader
```

实现批量数据的生成：

```python
class myDataset(Dataset):
    ''' 模拟计算电路数据生成器，默认小端在前
        Args:
                bitlen: 总线位宽
                datalen:数据个数
                padding:输入数据末尾填充0的个数
                ctype:  计算类型
                    'add'   加法运算
                    'mul'   乘法运算
                dtype:  数据结构
                  value           x-dataset              y-dataset(add/mul)
                    0       (datalen, 2*bitlen,)   (datalen, bitlen+1 / 2*bitlen,)
                    1       (datalen, bitlen, 2)   (datalen, bitlen+1 / 2*bitlen,)
                    2       (datalen, 2, bitlen)   (datalen, bitlen+1 / 2*bitlen,)
    '''
    def __init__(self, bitlen, datalen, padding=0, ctype='add', dtype=0):
        if ctype == 'add':
            outbit = bitlen + 1
            calopt = lambda a, b: a + b
        elif ctype == 'mul':
            outbit = bitlen * 2
            calopt = lambda a, b: a * b
        else:
            raise ValueError("Error in ctype:", ctype)

        if dtype == 0:
            megopt = lambda a, b: a + b
        elif dtype == 1:
            megopt = lambda a, b: list(zip(a, b))
        elif dtype == 2:
            megopt = lambda a, b: list(a, b)
        else:
            raise ValueError("Error in dtype:", dtype)

        num2bcd = lambda x, l: [1 & (x >> i) for i in range(l)]
        maxnum = (1 << bitlen) - 1

        if padding > 0:
            bitlen += int(padding)

        inputs, targets = [], []
        for i in range(datalen):
            a, b = random.randint(0, maxnum), random.randint(0, maxnum)
            inputs.append(megopt(num2bcd(a, bitlen), num2bcd(b, bitlen)))
            targets.append(num2bcd(calopt(a, b), outbit))

        self.dsin = np.array(inputs, dtype=np.float32)
        self.dsout = np.array(targets, dtype=np.float32)

    def __len__(self):
        return len(self.dsin)

    def __getitem__(self, idx):
        return (self.dsin[idx], self.dsout[idx])
```

### 三、模型实现

先设定超参数如下：

```python
bus_width = 32
learning_rate = 1e-3

print_step = 1000
epoches = print_step * 10

batch_size = 64
train_size = batch_size * 50
test_size = batch_size * 4
```

实现一个简单的线性网络：

```python
class Simulator(nn.Module):
    ''' A simulator of arithmetic circuits '''
    def __init__(self, bitlen):
        super(Simulator, self).__init__()
        self.bitlen = bitlen
        self.linear1 = nn.Linear(bitlen*2, bitlen*2)
        self.linear2 = nn.Linear(bitlen*2, bitlen*2)
        self.linear3 = nn.Linear(bitlen*2, bitlen+1)

    def forward(self, x):
        y = self.linear1(x).clamp(min=0)
        y = self.linear2(y).clamp(min=0)
        y = torch.sigmoid(self.linear3(y))
        return y
```

训练函数：

```python
def start_train(trainds, testds, model, criterion):
    train_loader = DataLoader(trainds, batch_size=batch_size, shuffle=True)
    test_loader = DataLoader(testds, batch_size=test_size, shuffle=True)

    if torch.cuda.is_available():
        model = model.cuda()
    optimizer = optim.Adam(model.parameters(), lr=learning_rate)
    model.train()

    for epoch in range(epoches):
        for inputs, target in train_loader:
            if torch.cuda.is_available():
                inputs = inputs.cuda()
                target = target.cuda()

            outputs = model(inputs)
            loss = criterion(outputs, target)

            optimizer.zero_grad()
            loss.backward()
            optimizer.step()

        if epoch % print_step == print_step - 1:
            for inputs, target in test_loader:
                if torch.cuda.is_available():
                    inputs = inputs.cuda()
                    target = target.cuda()
                rloss = criterion(torch.round(model(inputs)), target)
            print('Epoch{}, loss: {:.6f}, rloss: {:.6f}'.format(
                    epoch, loss.data, rloss.data))
```

开始训练：

```python
if __name__ == '__main__':
    train_dataset = myDataset(bus_width, train_size)
    test_dataset = myDataset(bus_width, test_size)
    model = Simulator(bus_width)
    start_train(train_dataset, test_dataset, model)
```

输出结果：

```shell
Epoch999, loss: 0.179174, aloss: 0.435606
Epoch1999, loss: 0.169170, aloss: 0.439394
Epoch2999, loss: 0.168272, aloss: 0.437618
Epoch3999, loss: 0.172583, aloss: 0.439157
Epoch4999, loss: 0.152697, aloss: 0.440341
Epoch5999, loss: 0.169740, aloss: 0.441288
Epoch6999, loss: 0.156561, aloss: 0.441525
Epoch7999, loss: 0.162197, aloss: 0.442590
Epoch8999, loss: 0.160881, aloss: 0.439039
Epoch9999, loss: 0.164809, aloss: 0.442472
```

然后结果就很迷了，无论是修改层数、修改隐含层个数还是更改`criterion`函数也好，输出结果均不理想。无奈，想起了之前尝试采用的`TFJS`时看到[别人的RNN方法][example_tfjs_rnn_add]，可以看到该方法是基于`NLP`处理方式实现的，但仍然是有参考意义，遂修改模型为`RNN`：

```python
class SimulatorRNN(nn.Module):
    def __init__(self, hsize=2):
        super(SimulatorRNN, self).__init__()
        self.rnn = nn.RNN(
            input_size = 2,
            hidden_size = hsize,
            num_layers = 1,
            batch_first = True,
            bidirectional = False
        )
        self.linear = nn.Linear(hsize, 1)
    def forward(self, x):
        # x shape   (batch, time_step, input_size=2)
        # out shape (batch, time_step, output_size=1)
        out, _ = self.rnn(x, None)
        out = self.linear(out)
        return torch.squeeze(out)

if __name__ == '__main__':
    train_dataset = myDataset(bus_width, train_size, padding=1, dtype=1)
    test_dataset = myDataset(bus_width, test_size, padding=1, dtype=1)
    model = SimulatorRNN()
    criterion = nn.MSELoss()
    start_train(train_dataset, test_dataset, model, criterion)
```

此时，输出结果就比较理想了：

```shell
Epoch999, loss: 0.084728, aloss: 0.111032
Epoch1999, loss: 0.001671, aloss: 0.000000
Epoch2999, loss: 0.000123, aloss: 0.000000
Epoch3999, loss: 0.000061, aloss: 0.000000
Epoch4999, loss: 0.000045, aloss: 0.000000
Epoch5999, loss: 0.000049, aloss: 0.000000
Epoch6999, loss: 0.000026, aloss: 0.000000
Epoch7999, loss: 0.000032, aloss: 0.000000
Epoch8999, loss: 0.000022, aloss: 0.000000
Epoch9999, loss: 0.000028, aloss: 0.000000
```

### 四、要点总结

#### 1、模型的优缺点

当前`RNN`模型的输出结果是全部`timestep`的输出序列，所以为了计算加法，需要对输入数据的末尾补零，以实现输入和输出的长度一致。

但是这样也会导致了模型在实现其他功能时往往需要更改结构，比如计算乘法时，输出的长度是输入的2倍，需要多对多处理。

验证输出时，往往需要将模型输出结果的值限定在`0`和`1`两个值上，然而`Pytorch`居然没有阶跃函数$$\varepsilon(x)$$，所以只好使用四舍五入`round`实现了（在结果为`0 ~ 1`附近有效）。

#### 2、其他问题

`RNN`模型偶尔无法收敛，或者收敛很慢，尤其是`batch_size`较大时，目前还没有头绪。

20191121 - 改为`LSTM`或`GRU`发现提升效果明显。


[2bit_add_cmos_layout]: /images/2bit_add_cmos.png
[example_tfjs_rnn_add]: https://orangecsy.github.io/2018/05/22/js-tfjs-5/
