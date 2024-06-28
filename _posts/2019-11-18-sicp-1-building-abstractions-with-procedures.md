---
layout: post
title:  "SICP-1-构造过程抽象"
date:   2019-11-18 15:16:07 +0800
categories: notes
description: "SICP笔记：第一章、构造过程抽象"
author: zburid
tags:   SICP Lisp
typora-root-url: ..
show:   true
---

### 一、程序设计的基本元素

#### 1、组合式

用一对括号括起一些表达式，形成一个表，用于表示一个过程应用：

```lisp
(* 10 34)
(/ 10 6)
(+ 483 23)
(- 32 23)
(+ 3.9 43)
```

表中最左端元素称为**运算符**，其他元素称为**运算对象**。运算符放在运算对象左边的形式称为**前缀表达**，完全适合用于带有任意个实参的过程，且不出现歧义：

```lisp
(+ 234 94 58 73)
(* 49 4 23)
```

第二个优点是可以直接扩充，允许出现组合式**嵌套**的情况：

```lisp
(+ (* 3 6) (- 10 8))
```

#### 2、变量

名字标识符，通过`define`的方式给事物命名：

```lisp
(define pi 3.1416)
(define radius 10)
(define circum (* 2 pi radius))
(define area (* pi (* radius radius)))
```

解释器维持相关的名字-值的相关存储能力被称为**环境**或**全局变量**。

#### 3、求值

要求一个组合式的值，会做下面的事情：

1. 求该组合式中各个子表达式的值
2. 将运算符（最左子表达式）对应的过程应用于相应的运算对象（其他子表达式，实际参数）

为实现对一个组合式的求值过程，必须先对组合式里的每个元素执行同样的求值过程，由此可以得出求值的普遍性质：

> 求值过程是**递归**的。

反复地应用第一个步骤，总可以将求值过程带到最后的某一点，在这里遇到的不是组合式而是基本表达式，如数、内部运算符或其他名字。处理基本情况的规定如下：

1. 数的值就是它们表达的数值。
2. 内部运算符的值就是能完成相应操作的机器指令序列
3. 其他名字的值就是在环境中关联与这个名字的对象

#### 4、复合

过程定义，可以为复合操作提供名字，而后就可以将这样的操作作为一个单元使用。其一般形式是：

`(define (<name> <formal parameters>) <body>)`

`<name>`是一个标号，过程定义将在环境中关联与这个符号。`<formal parameters>`（形式参数）是一些名字，用于表示过程应用时与它们对应的各个实际参数。`<body>`是一个表达式，应用过程时`<body>`中的形式参数将被与之对应的实际参数取代，产生过程应用的值。

```lisp
(define (average x y)
    (/ (+ x y) 2))
(average 10 20)         ==> 15

(define (square x)
        (* x x))
(square 21)             ==> 441
(square (+ 2 5))        ==> 49
(square (square 3))     ==> 81

(define (sum-of-squares x y)
    (+ (square x) (square y)))
(sum-of-squares 3 4)    ==> 25

(define (fun a)
    (sum-of-squares (+ a 1) (* a 2)))
(fun 5)                 ==> 136
```

#### 5、代换

复合过程应用的计算过程是：将复合过程应用于实际参数，就是在将过程体中的每个形参用相应的实参取代后，对这一过程体求值。比如求值 `(f 5)`：

    展开    ==>    (sum-of-squares (+ 5 1) (* 5 2))
    归约    ==>    (sum-of-squares 6 10)
    展开    ==>    (+ (square 6) (square 10))
    展开    ==>    (+ (* 6 6) (* 10 10))
    归约    ==>    (+ 36 100)
    归约    ==>    136

这种计算过程称为过程应用的**代换模型**，需要强调：

    代换的作用只是帮助领会过程调用中的情况，而不是解释器的实际工作方式。

另一种求值模型是先不求出运算对象的值，直到实际需要它们的值时再去求。采用这种方式求值时，应首先用运算对象表达式去代换形式参数，直到得到一个只含基本运算符的表达式，再去执行求值。比如求值 `(f 5)`：

    展开    ==>    (sum-of-squares (+ 5 1) (* 5 2))
            ==>    (+ (square (+ 5 1)) (square (* 5 2)))
            ==>    (+ (* (+ 5 1) (+ 5 1)) (* (* 5 2) (* 5 2)))
    归约    ==>    (+ (* 6 6) (* 10 10))
            ==>    (+ 36 100)
            ==>    136

这种*完全展开后再归约*的求值模型称为**正则序求值**，现在解释器里实际使用的是*先求值参数后应用*的方式称为**应用序求值**。应用序求值能避免对于表达式的重复求值。
通常可以总结如下：

应用序（Applicative-Order）求值：先递归对过程的所有的参数求值，然后将这些参数的值应用于该过程；

正则序（Normal-Order）求值：先将过程完全展开，直至得到只包含基本运算符的表达式，然后执行求值（规约）。

#### 6、条件

**分情况分析**：`cond` ，条件表达式的一般形式如下：

```lisp
(cond ( <p1> <e1> )
      ( <p2> <e2> )
      ...
      ( <pn> <en> ))
```

符号`cond`之后跟着的用括号括起来的表达式对偶(`<p>``<e>`)称为**子句**，每个对偶中的第一个表达式是一个**谓词**，它的值被解释为真或假。谓词是指那些返回真或假的过程，也指那些能求出真或假的表达式，基本谓词有大于`>`、小于`<`和等于`=`。

条件表达式的求值方式为：首先求值谓词`<p1>`，若为`false`则去求值`<p2>`，若`<p2>`为`false`则去求值`<p3>`——直到发现某个谓词为真，此时返回子句中序列表达式`<e>`的值。若无法找到真的`<p>`，则`cond`的值未定义。

符号**`else`**可用于`cond`的最后一个子句的`<p>`，表示如果该`cond`前面描述的所有子句都跳过的话，它将返回最后子句中`<e>`的值。

比如求绝对值：

```lisp
(define (abs x)
    (cond ((> x 0) x)
          ((= x 0) 0)
          ((< x 0) (- x))))
```

比如求3个数中较大的2个数的和：

```lisp
(define (max-2-plus-in-3 a b c)
    (- (+ a b c) (min-in-3 a b c)))
(define (min-in-3 x y z)
    (min-in-2 (min-in-2 x y) z))
(define (min-in-2 m n)
    (cond ((< m n) m)
          (else    n)))
```

符号`if`**是条件表达式的一种受限形式**，适用于分情况分析中只有两个情况的需要,一般形式是：

`(if <predicate> <consequent> <alternativ> )`

求值`if`表达式时，解释器从`<predicate>`部分开始求值，如果`<predicate>`得到真值，解释器就去求并返回`<consequent>`的值，否则去求并返回`<alternativ>`的值。

一般情况下，`if`可以用`cond else`取代，如下：

```lisp
(define (new-if predicate then-clause else-clause)
    (cond (predicate then-clause)
          (else      else-clause)))
```

`new-if`是一个**常规过程**，默认采用应用序求值，而`if`默认采用正则序求值。当涉及到参数是迭代处理等情况时，无论正则序还是应用序求值都会造成`new-if`表达式的无限展开，因此`new-if`**不能完全取代**`if`的使用。

**复合谓词**：由基本谓词`<`、`>`、`=`和逻辑复合运算符`and`、`or`、`not`构造。

`(and <e1> ... <en> )`：从左到右如果某个`<e>`为假，则`and`表达式为假且后面的`<e>`不用再求值，若前面的`<e>`都为真，则`and`表达式的值为最后那个`<e>`的值。

`(or <e1> ... <en> )`：从左到右如果某个`<e>`为真，则`or`表达式为真且后面的`<e>`不用再求值，若前面的`<e>`都为假，则`or`表达式的值为最后那个`<e>`的值。

`(not <e> )`：若`<e>`为假则`not`表达式为真，否则为假。

比如5 < x < 10的条件为：`(and (> x 5) (< x 10))`

比如定义大于等于：`(define (>= x y)  (or (> x y) (= x y)))`
或者：`(define (>= x y) (not (< x y)))`

比如求绝对值：

```lisp
(define (abs x)
    (if (< x 0)
        (- x)
        x))
```

比如求`a + abs(b)`：

```lisp
(define (a-plus-abs-b)
    ((if (> b 0) + -) a b))
```

比如求3个数中较大的2个数的和：

```lisp
(define (max-2-plus-in-3 a b c)
    (+  (if (> a b) a b)
        (if (> (if (> a b) b a) c)
            (if (> a b) b a)
            c)))
```

比如检测解释器所用的求值序：

```lisp
(define (p) (p))
(define (test x y)
    (if (= x 0)
        0
        y))
```

执行 `(test 0 (p))` 会出现什么现象？若为正则序求值，则展开方式为：

`(test 0 (p)) -> (if #t 0 (p)) -> 0`

因为正则序需要将过程完全展开，所以在展开if的时候，首先执行的是谓词`(= 0 0)`，此时立即得到结果0，而无须再对p求值。若为应用序求值，则解释器首先需要做的是递归对所有参数求值，所以展开方式为：

`(test 0 (p))` -> `(if #t 0 (p))` -> `(if #t 0 (p))` ->……

#### 7、实例

牛顿法求平方根：$$y=\sqrt{x}$$，近似值：$$(y+x/y)/2$$

1. 判断$$y$$是否足够精确$$abs(y^2-x)<0.001$$，如果是返回$$y$$的值并结束，否则执行第2步
2. 获取更好的$$y$$，$$y = (y+x/y)/2$$，执行第1步

程序如下：
```lisp
(define (sqrt x)
    (sqrt-iter 1.0 x))

(define (sqrt-iter guess x)
    (if (good-enough? guess x)
        guess
        (sqrt-iter (improve guess x) x)))

(define (good-enough? guess x)
    (< (abs (- (square guess) x)) 0.001))

(define (improve guess x)
    (average guess (/ x guess)))
```

如果使用`new-if`代替`if`重写`sqrt-iter`，程序将不能正确运行，这是由于`new-if`过程在计算过程中会无限展开。

```lisp
(define (sqrt-iter guess x)
    (new-if (good-enough? guess x)
        guess
        (sqrt-iter (improve guess x) x)))
```

对于很大或很小的数来说，函数`good-enough?`会有很大的乘法运算量，检测很可能会失败。另一种检测方法是每次迭代时，猜测值的改变量相对于猜测值的比率足够小时结束迭代，即判断条件是$$\Delta y/y < 0.001$$，重写函数如下：

```lisp
(define (sqrt x)
    (sqrt-iter 0 1.0 x))

(define (sqrt-iter old guess x)
    (if (good-enough? old guess)
        guess
        (sqrt-iter guess (improve guess x) x)))

(define (good-enough? old guess)
    (< (/ (abs (- old guess)) guess) 0.001))
```

尝试牛顿法求立方根：$$y=\sqrt[3]{x}$$近似值：$$(x/y2+2y)/3$$：

```lisp
(define (cbrt x)
(cbrt-iter 0 1.0 x))

(define (cbrt-iter old guess x)
    (if (good-enough? old guess)
        guess
        (cbrt-iter guess (improve guess x) x)))

(define (improve guess x)
    (/ (+ (/ x (* guess guess)) (* 2 guess))
       3))
```

#### 8、黑箱

对于`sqrt`的求解，从原问题分解为若干个子问题，分解中的每一个过程完成了一件可以清楚标明的工作，这使得它们可以被用作定义其他过程的模块。无需关注每个过程是如何计算出它的结果的，只需要注意它能计算出正确结果的事实，而如何计算的细节则隐去不提。一个过程定义能够隐藏起一些细节，这将使过程的使用者不必去写这些过程，而是从其他程序员那里作为一个**黑箱**而接收它。

用户不必关心过程的实现细节之一，就是在有关的过程中形式参数的名字。过程的形式参数名必须局部于有关的过程体，称为**约束变量**，一个过程的定义约束了它所有的形式参数。一个名字的定义被约束于的那一集表达式称为这个名字的**作用域**。

过程的形式参数是相应过程体里的局部名字。为将子过程局部化，使得该子过程能与其他相同功能的过程共存，可以采用在一个过程里带有内部定义，使它们局部于这一过程。这种嵌套的定义称为**块结构**，除了可以将所用的辅助过程定义放到内部，还可以简化它们，避免将参数值显示传递，使得某些值作为内部定义的自由变量，这种方式称为**词法作用域**。

比如求平方根，未简化版：

```lisp
(define (sqrt x)
    (define (improve guess x)
        (average guess (/ x guess)))
    (define (good-enough? old guess)
        (< (/ (abs (- old guess)) guess) 0.001))
    (define (sqrt-iter old guess x)
        (if (good-enough? old guess)
            guess
            (sqrt-iter guess (improve guess x) x)))
    (sqrt-iter 0 1.0 x))
```

简化参数版：

```lisp
(define (sqrt x)
    (define (improve guess)
        (average guess (/ x guess)))
    (define (good-enough? old guess)
        (< (/ (abs (- old guess)) guess) 0.001))
    (define (sqrt-iter old guess)
        (if (good-enough? old guess)
            guess
            (sqrt-iter guess (improve guess))))
    (sqrt-iter 0 1.0))
```

### 二、过程与它们所产生的计算

#### 1、线性递归和迭代

计算阶乘的**递归**方法：
> 对于一个正整数n，n!就是等于n乘以(n-1)!，且1!等于1。

```lisp
(define (factorial n)
    (if (= n 1)
        1
        (* n (factorial (- n 1)))))
```

该计算模型显示出一种先逐步展开后收缩的形态，展开过程中计算过程构造出一个推迟进行的操作所形成的链条，收缩阶段表现为这些运算的实际执行。计算阶乘n!时，推迟执行的乘法链条的长度随着n值而线性增长，称为**线性递归计算过程**。

计算阶乘的**迭代**方法：
> 对于一个正整数n，n!就是等于从1到n之间所有的正整数（包括n）的乘积。

```lisp
(define (factorial n)
    (define (iter product counter)
        (if (> counter n)
            product
            (iter (* counter product)
                  (+ counter 1))))
    (iter 1 1))
```

该计算模型中没有任何增长或者收缩，对于任何一个n，在计算过程中的每一步，只需要保存变量`product`、`counter`的当前值，计算n!时，所需的计算步骤随n线性增长，称为**线性迭代计算过程**。

一般来说，**迭代计算过程**就是那种其状态可以用固定数目的状态变量描述的计算过程；与此同时，又存在着一套固定的规则，描述了计算过程从一个状态到下一个状态转换时，这些变量的更新方式；还可能有一个结束检测，描述这一计算过程应该终止的条件。

*递归计算过程和递归过程是不同的概念*。说一个过程是递归的时候，论述的是一个语法形式的事实，说明这个过程的定义中直接或间接引用了该过程本身；说一个过程具有某种模式时，说的是这一计算过程的进展方式，而不是相应过程书写上的语法形式。`iter`过程是一个递归过程，但是它将产生一个迭代的计算过程。

常见语言如C、ADA等语言中在实现描述迭代过程时，必须借助特殊的“循环结构”，如`do`、`while`、`for`、`repeat`、`until`等，Scheme总能在常量空间中执行迭代型计算过程，即使这一计算是用递归过程描述的，具有这一特性的实现称为**尾递归**。有了尾递归，可以利用常规的过程调用机制描述迭代，也会使各种复杂的专用迭代结构变成不过是一些**语法糖**了。

#### 2、树形递归

斐波那契数列：数列中每个数字都是前面两个数之和，Fib(0) = 0，Fib(1) = 1。

```lisp
(define (fib n)
    (cond ((= n 0) 0)
          ((= n 1) 1)
          (else (+ (fib (- n 1))
                  (fib (- n 2))))))
```

该递归计算过程展开看像是一棵树，对`fib`过程的每次调用都两次递归调用自身，每层分裂为两个分支，称为**树形递归**。

![树形递归][tree-recursive]

一般地，*树形递归计算所需的步骤数正比于树中的节点数，空间需求正比于树的最大深度*。

将其改为迭代法，则没有递归法直观，如下：

```lisp
(define (fib n)
    (define (iter a b count)
        (if (= count 0)
            b
            (iter (+ a b) a (- count 1))))
    (iter 1 0 n))
```

例程1：换零钱方式统计：用半美元(50¢)、四分之一美元(25¢)、10¢、5¢和1¢的硬币，将任意给定的现金换成零钱，有多少种不同方式。

实际上即是需要求出类似于$$Ax+By+Cz=D$$方程的正整数解的全排列，简化需求，只需要求出全排列的个数。按照常人的思路，采用穷举法，$$x=0$$时求$$By+Cz=D$$的全排个数，$$x=1$$时求$$By+Cz=D-A$$的全排个数，$$x=2$$时求$$By+Cz=D-2A$$的全排个数……直到$$D-Ax$$小于0停止。而对于求降了元的$$By+Cz=N$$方程的全排个数，也可以采用相同的穷举法。最后将所有的全排个数加起来就是$$Ax+By+Cz=D$$方程的解的所有全排列个数。

整个处理过程中应注意到：一、方程$$Ax+By+Cz=D$$的元数的递减；二、未知数x、y或z的值的递增。将之应用在换零钱上，可采用以下思路：

    1、现金a换成除第一种硬币以外的所有其他硬币的不同方式数目，加上
    2、现金a-d换成所有种类的硬币的不同方式数目（d是第一种硬币的币值）

步骤1体现了元数的递减，步骤2体现了未知数的递增。还应注意到，如果a=0，算为一种换零钱方式；若a<0或硬币的类型遍历完毕（元数为0）应当停止递归。具体实现程序如下：

```lisp
(define (change amount)
    (define (iter amount kinds)
        (cond ((= amount 0) 1)
              ((or (< amount 0) (= kinds 0)) 0)
              (else (+ (iter amount (- kinds 1))
                      (iter (- amount (value kinds)) kinds)))))
    (define (value kinds)
        (cond ((= kinds 1) 1)
              ((= kinds 2) 5)
              ((= kinds 3) 10)
              ((= kinds 4) 25)
              ((= kinds 5) 50)))
    (iter amount 5))
```

例程2：函数$$f$$定义如下，请分别采用递归和迭代的方式写出计算f的过程：若$$n < 3$$，则$$f(n) = n$$，否则$$f(n) = f(n-1) + 2f(n-2) + 3f(n-3)$$

递归方法：

```lisp
(define (func n)
    (if (< n 3) n
        (+  (func (- n 1))
            (* 2 (func (- n 2)))
            (* 3 (func (- n 3))))))
```

迭代方法：如采用从下向上累加的方式，则当n为小数时，需要求出小数部分，目前还无法实现；采用从上向下累计的方式，只需要累计系数并降元即可。

```lisp
(define (func n)
    (define (iter n a b c)
        (if (< n 3)
            (+ (* a n) (* b (- n 1)) (* c (- n 2)))
            (iter (- n 1) (+ a b) (+ (* a 2) c) (* a 3))))
    (iter n 1 0 0))
```

#### 3、增长的阶

为粗略描述计算过程所需资源的度量情况，使用**增长的阶**的记法。令n为一个参数，作为问题规模的度量，如计算精度、矩阵乘法的阶数等；令$$R(n)$$为一个计算过程在处理规模为n的问题时所需的资源量，如所用寄存器数目量、所需机器操作数目量等。

如果存在与n无关的整数$$k_1$$和$$k_2$$，对于任意足够大的n都存在：$$k_1f(n)≤R(n)≤k_2f(n)$$

我们称$$R(n)$$具有$$\theta(f(n))$$的增长阶，记为$$R(n)=\theta(f(n))$$。某计算过程需要$$n^2$$步，另一计算需要$$1000n^2$$步，还有一计算需要$$3n^2+10n+17$$步，它们增长的阶都是$$\theta(n^2)$$。

在角x足够小时，其正弦值可以用sinx≈x计算，三角恒等式可以减小sin的参数的大小：$$sinx = 3 * sin(x/3)-4 * (sin(x/3))^3$$

```lisp
(define (cube x) (* x x x))
(define (p x) (- (* 3 x) (* 4 (cube x))))
(define (sine angle)
    (if (not (> (abs angle) 0.1))
        angle
        (p (sine (/ angle 3.0)))))
```

计算`(sine a)`过程使用的空间增长的阶为：$$\theta(logn)$$，步数增长的阶为：$$\theta(logn)$$。

#### 4、求幂

计算乘幂有多种方法，常规法如下：$$b_n=b * b_{n-1}, b_0=1$$

```lisp
(define (expt b n)
    (if (= n 0)    1
        (* b (expt b (- n 1)))))
```

以上递归法计算过程需要$$\theta(n)$$步和$$\theta(n)$$空间，等价于以下的线性迭代，只需要$$\theta(n)$$步和$$\theta(1)$$空间。

```lisp
(define (expt b n)
    (define (iter counter product)
        (if (= counter 0)
            product
            (iter (- counter 1) (* b product))))
    (iter n 1))
```

采用连续求平方法如下：

$$b_n=(b_{n/2})^2$$    若n为偶数
$$b_n=b * b_{n-1}$$    若n为奇数
$$b_0=1$$        若n为0

```lisp
(define (fast-expt b n)
    (cond  ((= n 0)    1)
            ((even? n)  (square (fast-expt b (/ n 2))))
            (else      (* b (fast-expt b (- n 1))))))
```

`fast-expt`中检测偶数的谓词基于**基本过程**`remainder`定义：

```lisp
(define (even? n)
    (= (remainder n 2) 0))
```

以上递归法计算过程需要$$\theta(logn)$$步，等价于以下的迭代法，

```lisp
(define (fast-expt b n)
    (define (iter counter product)
        (cond ((= counter n) product)
            ((or (> counter (/ n 2)) (= counter 0))
                (iter (+ counter 1) (* product b)))
            (else
                (iter (* counter 2) (square product)))))
    (iter 0 1))
```

例程1：假设基本过程中没有乘法只有加法，求两个数的乘积

```lisp
(define (mul a b)
    (if (= b 0)
        0
        (+ a (mul a (- b 1)))))
```

以上递归法类似于`expt`过程，使用一个求出一个整数的两倍的`double`运算和一个求出一个偶数的一半的`halve`运算，设计一类似于`fast-expt`的只用对数步的乘积运算如下：

```lisp
(define (mul a b)
    (cond ((= b 0) 0)
        ((even? b)
            (double (mul a (halve b))))
        (else
            (+ a (mul a (- b 1))))))
```

改为迭代过程如下：

```lisp
(define (mul a b)
    (define (iter counter product)
        (cond ((= counter b) product)
            ((or (> (double counter) b) (= counter 0))
                (iter (+ counter 1) (+ product a)))
            (else
                (iter (double counter) (double product)))))
    (iter 0 0))
```

例程2：$$\theta(logn)$$步求斐波那契数。常用变换规则如下，称为$$T$$变换

$$
\begin{bmatrix}1 & 1\\1 & 0\end{bmatrix}
\begin{bmatrix}a\\b\end{bmatrix}=
\begin{bmatrix}a+b\\a\end{bmatrix}=
\begin{bmatrix}a'\\b'\end{bmatrix}
$$

现将其抽象如下的变换$$T_{pq}$$，以上的变换规则仅是当$$p=0$$且$$q=1$$的特例：

$$
\begin{bmatrix}p+q & q\\q & p\end{bmatrix}
\begin{bmatrix}a\\b\end{bmatrix}=
\begin{bmatrix}ap+aq+bq\\aq+bp\end{bmatrix}=
\begin{bmatrix}a'\\b'\end{bmatrix}
$$

现假设存在一变换$$T_{p'q'}$$等同于$$T_{pq}^2$$，即相当于做了两次$$T_{pq}$$变换，则可求出$$T_{p'q'}$$如下：

$$
\begin{bmatrix}p+q & q\\q & p\end{bmatrix}
\begin{bmatrix}p+q & q\\q & p\end{bmatrix}=
\begin{bmatrix}(p+q)^2+q^2 & q^2+2pq\\q^2+2pq & q^2+p^2\end{bmatrix}=
\begin{bmatrix}p'+q' & q'\\q' & p'\end{bmatrix}
$$

可以计算出$$p'$$和$$q'$$的值，如下：

$$
\begin{bmatrix}p'\\q'\end{bmatrix}=
\begin{bmatrix}q^2+p^2\\q^2+2pq\end{bmatrix}
$$

即可采用连续求平方的方式去计算$$T_n$$，如下过程：

```lisp
(define (fib n)
    (define (iter a b p q count)
        (cond ((= count 0) b)
            ((even? count)
                (iter a
                      b
                      (+ (square q) (square p))
                      (+ (square q) (* p q 2))
                      (/ count 2)))
            (else
                (iter (+ (* b q) (* a q) (* a p))
                      (+ (* b p) (* a q))
                      p
                      q
                      (- count 1)))))
    (iter 1 0 0 1 n))
```

#### 5、最大公约数
如果`r`是`a`除以`b`的余数，那么`a`和`b`的公约数正好也是`b`和`r`的公约数。这一计算`GCD`方法称为欧几里得算法：

$$
GCD(a, b)=GCD(b, r) \quad r=a mod b
$$

```lisp
(define (gcd a b)
    (if (= b 0)
        a
        (gcd b (remainder a b))))
```

**Lame定理**：如果欧几里得算法需要用k步计算出一对整数的GCD，那么这对数中较小的一个必然大于或等于第k个斐波那契数。
证明？？？？？
若用正则序解释`gcd`过程，以`(gcd 206 40)`为例：

    (gcd 206 40) -> (if (= 40 0) 206 (gcd 40 (remainder 206 40)))
    (gcd 40 6)   -> (if (= 6 0) 40 (gcd 6 (remainder 40 6)))
    (gcd 6 4)    -> (if (= 4 0) 6 (gcd 4 (remainder 6 4)))
    (gcd 4 2)    -> (if (= 2 0) 4 (gcd 2 (remainder 4 2)))
    (gcd 2 0)    -> (if (= 0 0) 2 (gcd 0 (remainder 2 0)))
    2

解释器默认是使用正则序解释`if`的，如果采用应用序解释`gcd`过程，如下：

    (gcd 206 40)
    (if (= 40 0) 206 (gcd 40 (remainder 206 40)))
    (if #f 206 (if(= 6 0) 40 (gcd 6 (remainder 40 6))))
    (if #f 206 (if #f 40 (if (= 4 0) 6 (gcd 4 (remainder 6 4)))))
    (if #f 206 (if #f 40 (if #f 6 (if (= 2 0) 4 (gcd 2 (remainder 4 2))))))
    (if #f 206 (if #f 40 (if #f 6 (if #f 4 (if (= 0 0) 2 (gcd 0 (remainder 2 0)))))))

运行到`(remainder 2 0)`时出现错误。

#### 6、素数检测

寻找因子检测，在$$1 \sim \sqrt{n}$$之间检测因子，具有$$\theta(\sqrt{n})$$增长阶：

```lisp
(define (prime? n)
    (define (smallest-divisor n)
        (find-divisor n 2))
    (define (find-divisor n test-divisor)
        (cond ((> (square test-divisor) n) n)
              ((divides? test-divisor n) test-divisor)
              (else (find-divisor n (+ test-divisor 1)))))
    (define (divides? a b)
        (= (remainder b a) 0))
    (= n (smallest-divisor n)))
```

费马检查，基于费马小定理，具有$$\theta(logn)$$增长阶。**费马小定理**：如果$$n$$是一个素数，$$a$$是小于$$n$$的任意正整数，那么【$$a^n$$与$$a$$】模$$n$$同余，也即$$a^n$$模$$n$$余$$a$$（即$$a^{n-1}$$与$$n$$互质）。

$$
a^n\equiv a(mod n)
$$

因此判断一个数$$n$$是不是素数，可以采用以下算法：对于给定的整数$$n$$，随机任取一个$$a < n$$并计算出$$a_{n-1}$$模$$n$$的余数。如果结果不为1，那么$$n$$就肯定不是素数。如果为1，那么n是素数的机会就很大。然后再另取一个随机的a并采用同样方式检查，如果满足上述等式，那么对判断n是素数就有更大的信心。通过检查越来越多的a值，可以不断增加对有关结果的信心，这一算法称为**费马检查**。

计算一个数的幂对另一个数取模的结果，可以采用一种策略：对于任意的正整数$$x$$、$$y$$和$$m$$，有$$(xmodm) * (ymodm)=(x * y)mod m$$。在快速求平方的过程中只有乘法和平方运算，因此最后的取模运算也可以分解在乘法和平方运算中。程序如下：

```lisp
(define (expmod base exp m)
    (define (iter exp)
        (cond ((= exp 0) 1)
            ((even? exp)
                (remainder (square (iter (/ exp 2))) m))
            (else
                (remainder (* base (iter (- exp 1))) m))))
    (iter exp))
```

执行费马检查需要产生随机数验证，采用**基本过程**`random`，程序如下：

```lisp
(define (fermat-test n)
    (define (try-it a)
        (= (expmod a (- n 1) n) 1))
    (try-it (+ 1 (random (- n 1)))))
```

添加验证次数，如果每次验证都成功，则判定该数为素数，否则为假，程序如下：

```lisp
(define (fast-prime? n times)
    (cond ((= times 0) #t)
        ((fermat-test n) (fast-prime? n (- times 1)))
        (else #f)))
```

然而上述判定是不正确的，因为任一素数都是满足费马小定理的，但是满足费马小定理的数并不一定是素数，比如**Carmichael数**。

例程1：使用基本过程`runtime`设计一个过程，检查给定范围内各个奇数的素性,并显示这些过程需要的时间。

```lisp
(define (range-search range-low range-high)
    (if (= (remainder range-low 2) 0)
        (search-for-primes (+ range-low 1) range-high)
        (search-for-primes range-low range-high)))
(define (search-for-primes start-n max-n)
    (if (not (> start-n max-n))
        ((timed-prime-test start-n)
            (search-for-primes (+ start-n 2) max-n))
        (display " # ")))
(define (timed-prime-test n)
    (newline)
    (display n)
    (start-prime-test n (runtime)))
(define (start-prime-test n start-time)
    (if (prime? n)
        (report-prime (- (runtime) start-time))))
(define (report-prime elapsed-time)
    (display " *** ")
    (display elapsed-time))
```

### 三、用高阶函数做抽象

在作用上，过程也是一类抽象。然而在数值计算过程中，如果将过程限制为只能以数作为参数，那将严重地限制我们建立抽象的能力。因此我们可以构造出以过程作为参数或返回值的过程，这类能操作过程的过程称为**高阶过程**。

#### 1、过程作为参数

求和公式：

$$
\sum_{n=a}^{b}f(n)=f(a)+...+f(b)
$$

递归方法：

```lisp
(define (sum term a next b)
    (if (> a b)
        0
        (+ (term a) (sum term (next a) next b))))
```

迭代方法：

```lisp
(define (sum term a next b)
    (define (iter a result)
        (if (> a b)
            result
            (iter (next a) (+ result (term a)))))
    (iter a 0))
```

其中过程`term`和`next`作为高阶过程`sum`的参数，这样无论是求哪个过程的和，都可以套用这个公共的求和模板，而不必专门关心某个过程的求和方法。有了`sum`，我们可以用它作为基本构件，去形式化其他概念。

按照以下公式计算$$\pi$$的近似值：

$$
\frac{\pi}{8}\approx\frac{1}{1 * 3}+\frac{1}{5 * 7}+\frac{1}{9 * 11}+...
$$

```lisp
(define (pi-sum a b)
    (define (pi-term x) (/ 1.0 (* x (+ x 2))))
    (define (pi-next x) (+ x 4))
    (* 8 (sum pi-term a pi-next b)))
```

求函数$$f$$在区间`[a,b]`上的定积分的近似值，如下

$$
\int_{a}^{b}f\approx\left \lceil f(a+\frac{dx}{2})+f(a+dx+\frac{dx}{2})+ f(a+2dx+\frac{dx}{2})+...\right \rceil dx
$$

$$dx$$是一个很小的值，我们可以描述该公式为一个如下过程：

```lisp
(define (integral f a b dx)
    (define (add-dx x) (+ x dx))
    (* dx (sum f (+ a (/ dx 2.0)) add-dx b)))
```

**辛普森规则**下函数$$f$$在区间`[a,b]`上的定积分的近似值为：
$$
\int_{a}^{b}f\approx\frac{h}{3}\left [ y_0+4y_1+2y_2+4y_3+2y_4+...+2y_{n-2}+4y_{n-1}+y_n \right ]
$$

其中$$h=(b-a)/n$$，$$n$$为某个偶数，而$$y_k=f(a+kh)$$，则使用辛普森规则的过程如下：

```lisp
(define (integral-sp f a b n)
    (define right-n
        (if (= (remainder n 2) 0)
            n
            (- n 1)))
    (define h (/ (- b a) right-n))
    (define (add-k k) (+ k 2))
    (define (part-sum-f k)
        (+  (f (+ a (* k h)))
            (* 4 (f (+ a (* (+ k 1) h))))
            (f (+ a (* (+ k 2) h)))))
    (* (/ h 3.0) (sum part-sum-f 0 add-k (- right-n 1))))
```

乘积公式：

$$
\prod_{n=a}^{b}f(n)=f(a)*...*f(b)
$$

递归方法：

```lisp
(define (prod term a next b)
    (if (> a b)
        1
        (* (term a) (prod term (next a) next b))))
```

迭代方法：

```lisp
(define (prod term a next b)
    (define (iter a result)
        (if (> a b)
            result
            (iter (next a) (* result (term a)))))
    (iter a 1))
```

可以重写阶乘`factorial`如下：

```lisp
(define (factorial n)
    (define (foo x) (+ x 0))
    (define (inc x) (+ x 1))
    (prod foo 1 inc n))
```

按照以下公式计算$$\pi$$的近似值：

$$
\frac{\pi}{4}\approx\frac{2 * 4 * 4 * 6 * 6 * 8...}{3 * 3 * 4 * 4 * 7 * 7...}
$$

```lisp
(define (pi-prod n)
    (define (add-n n) (+ n 2))
    (define (square x) (* x x))
    (define (part-mul-f n)  (/ (- (square n) 1) (square n)))
    (* 4.0 (prod part-mul-f 3 add-n n)))
```

`sum`和`prod`都是另一个称为`accumulate`的更一般的情况，`accumulate`使用某些一般性的累计函数组合起一系列项：

```lisp
(accumulate combiner null-value term a next b)
```

过程`combiner`描述如何将当前项与前面各项结果积累起来，`null-value`参数描述在所有项用完时的基本值，`accumulate`过程如下：

递归方法：

```lisp
(define (accumulate combiner null-value term a next b)
    (if (> a b)
        null-value
        (combiner (term a)
            (accumulate combiner null-value term (next a) next b))))
```

迭代方法：

```lisp
(define (accumulate combiner null-value term a next b)
    (define (iter a result)
        (if (> a b)
            result
            (iter (next a) (combiner result (term a)))))
    (iter a null-value))
```

滤波器`filter-accumulate`是一种比`accumulate`更加一般的过程，在计算过程中只组合给定范围内的项里满足特定条件的项，相当于在原有的`accumulate`过程中添加有关`filter`的谓词参数。

递归方法：

```lisp
(define (filter-accumulate filter combiner null-value term a next b)
    (if (> a b)
        null-value
        (combiner
            (filter-accumulate filter combiner null-value term (next a) next b)
            (if (filter (term a))
                (term a)
                null-value))))
```

迭代方法：

```lisp
(define (filter-accumulate filter combiner null-value term a next b)
    (define (iter a result)
        (if (> a b)
            result
            (iter (next a)
                (combiner result
                    (if (filter (term a))
                        (term a)
                        null-value)))))
    (iter a null-value))
```

求出在区间a到b之间所有素数之和：

```lisp
(define (prime-sum a b)
    (define (divides? a b) (= (remainder b a) 0))
    (define (square x) (* x x))
    (define (add x y) (+ x y))
    (define (inc x) (+ x 1))
    (define (foo x) x)
    (define (prime? n)
        (define (smallest-divisor n)
            (find-divisor n 2))
        (define (find-divisor n test-divisor)
            (cond ((> (square test-divisor) n) n)
                  ((divides? test-divisor n) test-divisor)
                  (else (find-divisor n (+ test-divisor 1)))))
        (= n (smallest-divisor n)))
    (filter-accumulate prime? add 0 foo a inc b))
```

求出所有小于n且与n互素的正整数之积：

$$
\prod_{i=1}^{n}(GCD(i,n)=1)
$$

```lisp
(define (gcd-prod n)
    (define (mul x y) (* x y))
    (define (inc x) (+ x 1))
    (define (foo x) x)
    (define (gcd a b)
        (if (= b 0)
            a
            (gcd b (remainder a b))))
    (define (gcd? i)
        (= (gcd i n) 1))
    (filter-accumulate gcd? mul 1 foo 1 inc n))
```

#### 2、lambda构造过程

在构造`pi-sum`过程时我们还需要定义`pi-term`和`pi-next`之类的简单函数，并用它们作为高阶函数的参数。为更简单地定义高阶函数而不想要显式地定义这些简单函数时，我们可以引用**`lambda`**特殊形式完成这类描述。

```lisp
(define (pi-sum a b)
    (sum (lambda (x) (/ 1.0 (* x (+ x 2))))
        a
        (lambda (x) (+ x 4))
        b))
(define (integral f a b dx)
    (* (sum f
            (+ a (/ dx 2.0))
            (lambda (x) (+ x dx))
            b)
        dx))
```

除了不为相关过程提供名称外，`lambda`用与`define`同样的方式创建过程：

```lisp
(lambda (<formal-parameters>) <body>)

((lambda (x y z) (+ x y (square z))) 1 2 3) /* lambda表达式用作组合式的运算符 */
```

`lambda`表达式除了可以创建已经约束为过程参数的变量外，还可以用来创建描述约束局部变量的匿名过程。

```lisp
(define (f x y)
    (define (f-helper a b)
        (+  (* x (square a))
            (* y b)
            (* a b)))
    (f-helper (+ 1 (* x y))
              (- 1 y)))
(define (f x y)
    ((lambda (a b)
        (+  (* x (square a))
            (* y b)
            (* a b)))
    (+ 1 (* x y))
    (- 1 y)))
```

为更方便地使用`lambda`表达式描述约束局部变量的匿名过程，可以使用`let`表达式使这种编程方式更方便。

```lisp
((lambda (<var1> <var2>...<varn>)
    <body>)
<exp1> <exp2>...<expn>)

(let ((<var1> <exp1>)   /* 在body里var1的值为exp1 */
      (<var2> <exp2>)   /* 在body里var2的值为exp2 */
      ...
      (<varn> <expn>))  /* 在body里varn的值为expn */
    <body>)

(define (f x y)
    (let ((a (+ 1 (* x y))) (b (- 1 y)))
        (+  (* x (square a))
            (* y b)
            (* a b))))
```

`let`表达式可以看作是`lambda`表达式的语法糖，由`let`表达式描述的变量的作用域便是`let`的`<body>`，这意味着`let`使人能在尽可能接近其使用的地方建立局部变量约束，且变量的值是在`let`之外计算的。

```lisp
(+ (let ((x 3))         /* 无论外部x的值为多少，let的作用域中x=3 */
        (+ x (* x 10))) /* let作用域之内的x */
    x)                  /* let作用域之外的x */
(let ((x 3)             /* 无论外部x的值为多少，let的作用域中x=3 */
      (y (+ x 2)))      /* 赋值给y的表达式中x的值为外部的x */
    (* x y))            /* let作用域之内的x */
```

假设定义了：`(define (f g) (g 2))`，那么就有：

    (f square)                      ==> 4
    (f (lambda (z) (* z (+ z 1))))  ==> 6

如果求值`(f f)`会发生什么？无法运行，`f`不是一个可以应用于参数的函数：

```shell
> (f f)
application: not a procedure;
  expected a procedure that can be applied to arguments
  given: 2
    arguments...:
    2
```

#### 3、过程作为一般性方法

例程1：使用二分法求方程$$f(x)=0$$的根，如果对于给定的两个点$$a$$和$$b$$有$$f(a) < 0 < f(b)$$，那么$$f$$在$$a$$和$$b$$之间必然有一个零点。

```lisp
(define (close-enough? x y)
    (< (abs (- x y)) 0.001))
(define (positive? x)
    (> x 0))
(define (negative? x)
    (< x 0))
(define (average x y)
    (/ (+ x y) 2))
(define (search f neg-point pos-point)
    (let ((midpoint (average neg-point pos-point)))
        (if (close-enough? neg-point pos-point)
            midpoint
            (let ((test-value (f midpoint)))
                (cond ((positive? test-value)
                        (search f neg-point midpoint))
                      ((negative? test-value)
                        (search f midpoint pos-point))
                      (else midpoint))))))
(define (half-interval-method f a b)
    (let ((a-value (f a))
          (b-value (f b)))
        (cond ((and (negative? a-value) (positive? b-value))
                (search f a b))
              ((and (negative? b-value) (positive? a-value))
                (search f b a))
              (else
                (error "Values are not of opposite sign" a b)))))
```

例程2：找出函数的**不动点**：如果$$x$$满足方程$$f(x)=x$$，则称$$x$$为函数$$f$$的不动点。对于某些函数，通过某个初始值开始，反复应用函数$$f$$：$$f(x),f(f(x)),f(f(f(x))),...$$直到值的变化不大时，就可以找到它的一个不动点。

```lisp
(define tolerance 0.00001)
(define (fixed-point f first-guess)
    (define (close-enough? v1 v2)
        (< (abs (- v1 v2)) tolerance))
    (define (try guess)
        (let ((next (f guess)))
            (if (close-enough? guess next)
                next
                (try next))))
    (try first-guess))
```

我们完全可以将平方根的计算形式化为一个寻找不动点的计算过程，计算某个数$$x$$的平方根，即是要找到一个$$y$$使得$$y^2=x$$，即需要寻找函数$$y \mapsto x/y$$的不动点，过程如下：

```lisp
(define (sqrt x)
    (fixed-point (lambda (y) (/ x y)) 1.0))
```

然而上述过程并不收敛，因为任意一个初始猜测$$y_1$$下，后续的猜测为$$y_2=x/y_1$$，$$y_3=x/y_2=y_1$$，过程陷入了一个无限循环中。为避免发生这样的无限循环发生，可以取$$(1/2)(y+x/y)$$作为下一个猜测，计算过程也变为了寻找函数$$y \mapsto (y+x/y)/2$$的不动点，过程如下：

```lisp
(define (sqrt x)
    (fixed-point (lambda (y) (average y (/ x y))) 1.0))
```

这种取逼近一个解的一系列值的平均值的方法，是一种称为**平均阻尼**的技术，常用于在寻找不动点中作为帮助收敛的手段。

例程3：证明黄金分割率$$\phi$$是函数$$x \mapsto 1+1/x$$的不动点，并通过`fixed-point`计算出$$\phi$$的值。

$$
\because \phi ^2 = \phi + 1 \therefore \phi = 1 + 1/\phi
$$

```lisp
(define (phi)
    (fixed-point (lambda (x) (+ 1 (/ 1 x))) 1.0))

> (phi)
1.6180327868852458
```

例程4：修改`fixed-point`使其能够打印出求不动点的过程，并求出$$x \mapsto log(1000)/log(x)$$的不动点和$$x^x=1000$$的一个根。试比较采用平均阻尼和不采用平均阻尼的步数区别。

```lisp
(define tolerance 0.00001)
(define (fixed-point f first-guess)
    (define (close-enough? v1 v2)
        (< (abs (- v1 v2)) tolerance))
    (define (try guess)
        (let ((next (f guess)))
            (display "guess = ")
            (display guess)
            (display "\tnext = ")
            (display next)
            (newline)
            (if (close-enough? guess next)
                next
                (try next))))
    (try first-guess))
(define (xlogx) /* 不采用平均阻尼大概需要23步 */
    (fixed-point (lambda (x) (/ (log 1000) (log x))) 4.5))
(define (xlogx) /* 采用平均阻尼大概只需要 6步 */
    (fixed-point (lambda (x) (average x (/ (log 1000) (log x)))) 4.5))
```

例程5：一个**无穷连分式**是如下的表达式：

$$
f=\frac{N_1}{D_1+\frac{N_2}{D_2+\frac{N_3}{D_3+...}}} \;\; \frac{N_1}{D_1+\frac{N_2}{\ddots +\frac{N_K}{D_K}}}
$$

可以证明当所有的$$N_i$$和$$D_i$$都等于1时，$$f=1/\phi$$。为逼近某个无穷连分式的一种方法是在给定数目的项之后截断，这样的一个截断称为**k项有限连分式**。分别用递归和迭代的方法求k项有限连分式，并判断$$N_i$$和$$D_i$$都等于1的情况下k取值为多大才能得到具有4位精度的$$1/\phi$$近似值。

```lisp
(define (cont-frac n d k)
    (define (frac-iter i)
        (let ((ni (n i)) (di (d i)) (nexti (+ i 1)))
            (if (= i k)
                (/ ni di)
                (/ ni (+ di (frac-iter nexti))))))
    (frac-iter 1))

(define (cont-frac n d k)
    (define (frac-iter i res)
        (let ((newres (/ (n i) (+ (d i) res)))
              (nexti (- i 1)))
            (if (= i 0)
                res
                (frac-iter nexti newres))))
    (frac-iter k 0))

> (cont-frac (lambda (i) 1.0) (lambda (i) 1.0) 15)
0.6180344478216819
```

例程6：自然对数的底$$e$$有这样一个连分式：$$e-2$$的连分式展开后$$N_i=1$$，$$D_i$$依次为1,2,1,1,4,1,1,6,1,1,8...请求出$$e$$的近似值：

```shell
> (+ 2 (cont-frac (lambda (i) 1.0)
    (lambda (i)
        (let ((imod3 (remainder i 3)))
            (if (= imod3 2)
                (* 2 (+ (/ (- i imod3) 3) 1))  /* 最好找个整除的方法 */
                1)))
    15))
2.718281828470584
```

例程7：正切函数的连分式如下，请定义`(tan-cf x k)`求正切函数的近似值。

$$
tanx=\frac{x}{1-\frac{x^2}{3-\frac{x^2}{5-\ddots}}}
$$

```lisp
(define (tan-cf x k)
    (cont-frac
        (lambda (i) (if (= i 1) x (- 0 (square x))))
        (lambda (i) (- (* i 2) 1))
        k))

> (tan-cf (/ PI 4) 20)
1.0000000002051033
```

#### 4、过程作为返回值

以用不动点的方法求平方根为例。在给定了一个函数$$f$$后，可以考虑另一个函数，它在$$x$$处的值等于$$x$$和$$f(x)$$的平均值：

```lisp
(define (average-damp f)
    (lambda (x) (average x (f x))))
```

过程`average-damp`的参数是一个过程`f`，返回值是另一个由`lambda`表达式产生的过程，我们将这一返回值应用于数$$x$$时，得到的将是$$x$$和$$f(x)$$的平均值。利用`average-damp`可以重写之前的求平方根公式过程如下，其中糅合了三种思想在同一个方法里：不动点搜寻，平均阻尼和函数$$y\mapsto x/y$$：

```lsip
(define (sqrt x)
    (fixed-point (average-damp (lambda (y) (/ x y)))
                1.0))
```

以**牛顿法**为例，如果$$x\mapsto g(x)$$是一个可微函数，那么方程$$g(x)=0$$的一个解就是函数$$x\mapsto f(x)$$的一个不动点，其中：

$$
f(x)=x-\frac{g(x)}{g'(x)}
$$

$$g'(x)$$是$$g(x)$$对$$x$$的导数，牛顿法便是使用不动点方法，通过搜寻函数$$f$$的不动点的方式，去逼近方程$$g(x)=0$$的解。为实现牛顿法的过程，首先需要描述导数的思想：

$$
g'(x)=\frac{g(x+dx)-g(x)}{dx}
$$

```lisp
(define dx 0.00001)
(define (deric g)
    (lambda (x)
        (/ (- (g (+ x dx)) (g x))
            dx)))
```

`deriv`与`average-damp`相同，以过程为参数并返回另一个过程。牛顿法可以表述为一个求不动点的过程，用牛顿法求$$x$$的平方根，即是用牛顿法找函数$$y\mapsto y^2-x$$的零点，如下：

```lisp
(define (newton-transform g)
    (lambda (x)
        (- x (/ (g x) ((deriv g) x)))))
(define (newton-method g guess)
    (fixed-point (newton-transform g) guess))
(define (sqrt x)
    (newton-method (lambda (y) (- (square y) x))
                    1.0))
```

以上两种方式都能将平方根计算描述为某种更一般方法的实例，都是从一个函数出发，找出这个函数在某种变换下的不动点。可以将这种具有普遍性的思想表述为一个函数：

```lisp
(define (fixed-point-of-transform g transform guess)
    (fixed-point (transform g) guess))
```

可以利用这一抽象重写平方根的计算过程：

```lisp
(define (sqrt x)
    (fixed-point-of-transform (lambda (y) (/ x y))
                              average-damp
                              1.0))
(define (sqrt x)
    (fixed-point-of-transform (lambda (y) (- (square y) x))
                              newton-transform
                              1.0))
```

高阶过程的重要性，在于使我们能显式地用程序设计语言的要素去描述这些抽象，使我们能像操作其他计算元素一样去操作它们。
一般而言，程序设计语言总会对计算元素的可能使用方式强加上某些限制。带有最少限制的元素被称为具有**第一级**的状态。第一级元素的某些*特权*包括：

    1. 可以用变量命名
    2. 可以提供给过程作为参数
    3. 可以由过程作为结果返回
    4. 可以包含在数据结构中

Lisp不像其他程序设计语言，它给了过程完全的第一级状态，这就给有效实现提出了挑战，但由此所获得的描述能力却是极其惊人的。

例程1：定义一个过程`cubic`，它和`newtons-method`过程一起使用在表达式`(newtons-method (cubic a b c) 1)`，能够逼近三次方程$$x^3+ax^2+bx+c$$的零点。

```lisp
(define (cubic a b c)
    (lambda (x) (+ (* x (+ (* x (+ x a)) b)) c)))
```

例程2：定义一个过程`double`，能够以一个有一个参数的过程作为参数并返回一个过程，该过程能够将原来的那个参数过程应用两次。例如`inc`过程能给参数加1，那么`(double inc)`将给参数加2，那么表达式`(((double (double double)) inc) 5)`返回什么？

```lisp
(define (double f)
    (lambda (x) (f (f x))))
(define (inc x)
    (+ x 1))

> (((double (double double)) inc) 5)
21
```

例程3：令$$f$$和$$g$$都是两个单参数的函数，定义复合函数$$h(x)=f(g(x))$$。请定义一个过程`compose`实现函数复合：

```lisp
(define (compose f g)
    (lambda (x) (f (g x))))

> ((compose square inc) 6)
49
```

例程4：若$$f$$是一个数值函数，$$n$$是一个正整数，那么可以构造出$$f$$的$$n$$次重复应用，将其定义为一个函数，该函数在$$x$$的值为$$f(f(...(f(x))...))$$。

```lisp
(define (repeated f n)
    (lambda (x)
        (if (> n 1)
            (compose f (repeated f (- n 1)))
            f)))
```


[tree-recursive]: /images/tree-recursive.png
