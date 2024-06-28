---
layout: post
title:  "使用Numpy实现全连接神经网络"
date:   2019-10-17 17:11:01 +0800
categories: notes
description: "使用Numpy实现全连接神经网络——dense层，包含公式推导和代码实现"
author: zburid
tags:   Numpy 神经网络 全连接 深度学习 反向传播
typora-root-url: ..
show:   true
---
### 一、简述

要求：使用`Numpy`实现两层全连接神经网络，输出每次迭代后的误差值，另外要求加入偏置`Bias`并采用`Relu`作为隐含层激活函数。

![FullConnectNN演示图][FullConnectNN]

如上图所示，原始数据$$x$$经过第一层网络计算得到$$h$$，再经过激活函数$$f$$得到$${h}'$$，$${h}'$$最后经过第二层网络计算得到$$\hat{y}$$。

### 二、公式推导

#### 1、正向传播

$$
h=xw_{1}+b_{1}
$$

$$
{h}'=f(h)
$$

$$
\hat{y}={h}'w_{2}+b_{2}
$$

其中，激活函数$$f$$采用了`Relu`：

$$
f(x)=relu(x)=max(0,x)
$$

#### 2、计算误差
采用方差和作为总的误差`Error`：

$$
e=\sum(\hat{y}-y)^2
$$

#### 3、计算偏导数

误差$$e$$对实际输出$$\hat{y}$$的偏导数：

$$
\frac{\partial e}{\partial \hat{y}} = 2(\hat{y} - y)
$$

实际输出$$\hat{y}$$对激活输出$${h}'$$、第二层权重$$w_2$$和第二层偏置$$b_2$$的偏导数：

$$
\frac{\partial \hat{y}}{\partial {h}'} = w_2 \quad \frac{\partial \hat{y}}{\partial w_2} = {h}' \quad \frac{\partial \hat{y}}{\partial b_2} = 1
$$

激活输出$${h}'$$对第一层输出$$h$$的偏导数：

$$
\frac{\partial {h}'}{\partial h} = \varepsilon(h)
$$

第一层输出$$h$$对第一层权重$$w_1$$和第一层偏置$$b_1$$的偏导数：

$$
\frac{\partial h}{\partial w_1} = x \quad \frac{\partial h}{\partial b_1} = 1
$$

#### 4、反向传播

反向传播更新第二层权重$$w_2$$和偏置$$b_2$$：

$$
{w}'_2 = w_2 - \eta \frac{\partial e}{\partial w_2} = w_2 - \eta \frac{\partial e}{\partial \hat{y}} \frac{\partial \hat{y}}{\partial w_2}
$$

$$
{b}'_2 = b_2 - \eta \frac{\partial e}{\partial b_2} = b_2 - \eta \frac{\partial e}{\partial\hat{y}} \frac{\partial \hat{y}}{\partial b_2}
$$

反向传播更新第一层权重$$w_1$$和偏置$$b_1$$：

$$
{w}'_1 = w_1 - \eta \frac{\partial e}{\partial w_1} = w_1 - \eta \frac{\partial e}{\partial h} \frac{\partial h}{\partial w_1}
$$

$$
{b}'_1 = b_1 - \eta \frac{\partial e}{\partial b_1} = b_1 - \eta \frac{\partial e}{\partial h} \frac{\partial h}{\partial b_1}
$$

其中根据链式法则，由第三步式子可以得出：

$$
\frac{\partial e}{\partial h} = \frac{\partial e}{\partial \hat{y}} \frac{\partial \hat{y}}{\partial {h}'} \frac{\partial {h}'}{\partial h}
$$

### 三、代码实现
```python
import numpy as np

def model(x, y, hsize, epoch=500, lr=1e-6):
    ''' Numpy 双层神经网络 model
        Args:
            x       输入数据[batch_size, insize]
            y       期望数据[batch_size, outsize]
            hsize   隐含层宽度
            epoch   训练轮次
            lr      学习率
    '''
    # get input/output shape
    insize, outsize = x.shape[-1], y.shape[-1]

    # parameters initial
    w1 = np.random.randn(insize, hsize)
    b1 = np.random.randn(hsize)
    w2 = np.random.randn(hsize, outsize)
    b2 = np.random.randn(outsize)

    for i in range(epoch):
        # feed forward
        h = np.add(np.dot(x, w1), b1)
        h_relu = np.maximum(h, 0)
        pred = np.add(np.dot(h, w2), b2)

        # calculate average loss
        error = np.square(pred - y).sum()
        if i % 50 == 49:
            print("epoch %d with loss %.04f" % (i+1, error))

        # back propagation
        grad_pred = 2 * (pred - y)
        grad_h_relu = np.dot(grad_pred, w2.T)
        grad_h_relu[h < 0] = 0.0             # 注意阶跃函数的自变量是 h
        grad_h = grad_h_relu

        # update parameters
        w2 -= lr * np.dot(h_relu.T, grad_pred)
        b2 -= lr * np.sum(grad_pred, axis=0) # 与一个全为1的矩阵点积该grad矩阵等同
        w1 -= lr * np.dot(x.T, grad_h)
        w1 -= lr * np.sum(grad_h, axis=0)    # 与一个全为1的矩阵点积该grad矩阵等同

if __name__ == '__main__':
    train_x = np.random.randn(64, 1000)
    train_y = np.random.randn(64, 10)

    model(train_x, train_y, 100)
```
运行结果如下：
```bash
epoch 50 with loss 47088.9376
epoch 100 with loss 674.3413
epoch 150 with loss 13.6512
epoch 200 with loss 0.3062
epoch 250 with loss 0.0073
epoch 300 with loss 0.0002
epoch 350 with loss 0.0000
epoch 400 with loss 0.0000
epoch 450 with loss 0.0000
epoch 500 with loss 0.0000
```

### 四、要点总结

#### 1、激活函数`Relu`的求导

`Relu`函数的表达式如下：

$$
f(x)=\left\{\begin{matrix}
0 & x < 0 \\
x & x \geqslant 0
\end{matrix}\right.
$$

分别在$$x$$为负和为正时求导得到阶跃函数：

$$
{f}'(x) = \varepsilon(x) = \left\{\begin{matrix}
0 & x < 0 \\
1 & x \geqslant 0
\end{matrix}\right.
$$

所以在计算反向传播梯度时，需要判断$$x$$的值为负时将上层传来的梯度赋值为0，以完成与上层梯度相乘的效果：

```python
grad_h_relu[h < 0] = 0.0
```

#### 2、作用于参数的梯度计算

在更新参数时，通常的做法都是用该层输出的转置与梯度的内积，然后乘以学习率作为参数减除量：

$$
{p}'=p - \eta *  out^T \cdot grad
$$

这是因为计算偏导数和反向传播这两步的推导是不够严谨的，向量函数的导数与常量函数不是一致的，参考[`nndl-book`](https://nndl.github.io/nndl-book.pdf)的B.3.1小节**链式法则**和B.4.1小节**向量函数及其导数**有：

$$
\frac{\partial \pmb{g}}{\partial x}=\frac{\partial \pmb{u}}{\partial x} \frac{\partial \pmb{g}}{\partial \pmb{u}}=(\frac{\partial \pmb{g}}{\partial \pmb{u}})^T \frac{\partial \pmb{u}}{\partial x}
$$

$$
\quad \frac{\partial \pmb{x}}{\partial \pmb{x}}=I \quad \frac{\partial A\pmb{x}}{\partial \pmb{x}}=A^{T} \quad \frac{\partial \pmb{x}^{T}A}{\partial \pmb{x}}=A
$$

所以重新推计算偏导数和反向传播这两步的公式如下：

$$
{w}'_2 = w_2 - \eta \frac{\partial e}{\partial w_2} = w_2 - \eta \frac{\partial \hat{y}}{\partial w_2} \frac{\partial e}{\partial \hat{y}} = w_2 - \eta {h}'^T \frac{\partial e}{\partial \hat{y}}
$$

$$
{b}'_2 = b_2 - \eta \frac{\partial e}{\partial b_2} = b_2 - \eta \frac{\partial \hat{y}}{\partial b_2} \frac{\partial e}{\partial \hat{y}} = b_2 - \eta I^T \frac{\partial e}{\partial \hat{y}}
$$

$$
\frac{\partial e}{\partial h} = (\frac{\partial e}{\partial \hat{y}})^T (\frac{\partial \hat{y}}{\partial {h}'})^T \frac{\partial {h}'}{\partial h}
$$

$$
{w}'_1 = w_1 - \eta \frac{\partial e}{\partial w_1} = w_1 - \eta \frac{\partial h}{\partial w_1} \frac{\partial e}{\partial h} = w_1 - \eta x^T \frac{\partial e}{\partial h}
$$

$$
{b}'_1 = b_1 - \eta \frac{\partial e}{\partial b_1} = b_1 - \eta \frac{\partial h}{\partial b_1} \frac{\partial e}{\partial h} = b_1 - \eta I^T \frac{\partial e}{\partial h}
$$


[FullConnectNN]: /images/full_connect_nn.png
