---
layout: post
title:  "使用Jekyll在Github建站"
date:   2019-10-16 09:25:16 +0800
categories: notes
description: "一个简易的使用Jekyll建站并部署到Github上的记录"
author: zburid
tags:   Jekyll 建站 Github
typora-root-url: ..
---

### 一、使用`Jekyll`搭建网站
[`Jekyll`][jekyllrb]是一个由`Ruby`语言开发的将纯文本转化为静态网站和博客的工具，在安装`Jekyll`之前需要先安装`Ruby`解释器：

```bash
pacman -S ruby
```

可能需要将`gem`的安装包的路径添加到`$PATH`中去，否则无法执行`gem`已安装的安装包：

```bash
echo 'export PATH=$PATH:/root/.gem/ruby/2.6.0/bin'>>/root/.bashrc
```

参照`Jekyll`[中文官网][jekyll-cn-site]上的操作，安装相关工具包：

```bash
gem install bundler jekyll
jekyll new myBlog
cd myBlog/
bundle exec jekyll serve
```

此时使用浏览器访问`http://localhost:4000`，就能看到一个简易网站成功运行了。
如果需要在局域网中访问的话，需要设置服务器监听所有网址：

```bash
bundle exec jekyll serve --host=0.0.0.0
```

### 二、上传至`Github`仓库
首先需要在`Github`个人页面创建仓库，仓库名如`xxx.github.io`，其中`xxx`一般是个人用户名。创建成功后就可以使用`git`命令克隆该仓库：

```bash
git clone https://github.com/xxx/xxx.github.io.git
```

克隆完成后，将`myBlog/`和`xxx.github.io`两个文件夹合并，添加并推送到远程仓库即可：

```bash
git add ./*
git commit -m "add jekyll"
git push
```

再访问`https://xxx.github.io/`就能看到博客已部署到`Github`上了。

### 三、之前的方案

#### 1、初始构想
最开始的想法就是搭建一个尽量由前端进行解析的博客架构，前端与后端在实现上最好没有多少耦合。

![之前方案的博客架构图][OldBlogArch]

#### 2、具体操作
首先预设置的每个文章链接都是如`http://hostname/article.html#AAA/BBB.md`的格式，在加载完`article.html`后，其中的JS代码会获取到该页面URL的`hash`——每个`hash`都是一篇文章的[`MarkDown`][MarkDown]格式的博客文件相对路径，然后采用`XHR`（XMLHttpRequest）的方式向服务器请求该博客数据：

```javascript
$(document).ready(function() {
    var hashurl = decodeURIComponent(window.location.hash);
    if(hashurl.length != 0) {
        var mdurl = hashurl.substr(1);
        document.title += " - " + mdurl.split('/').slice(-1);
        $.get(mdurl, function(data) {
            // TODO: Deal with markdown file
        });
    }
    else
        $(location).attr('href', '404.html');
}
```

获取数据后使用[`Strapdown.js`][Strapdown.js]直接解析`MarkDown`文本为网页内容：

```javascript
var converter = new showdown.Converter({
    tables: true,
    strikethrough: true,
    literalMidWordUnderscores: true
}); 
article_html = converter.makeHtml(data);
```

由于`Strapdown.js`不能解析`LaTex`公式，还需要加入[`Katex.js`][Katex.js]解析公式内容：

```javascript
var count = 0;
function render(data) {
    return data.replace(/\${2,3}(.+?)\${2,3}/g, function(str) {
        var sidx = str[2] == '$' ? 2 : 1;
        var lstr = str.slice(sidx, str.length-sidx).replace(/\\/g, "\\\\").replace(/\<\/{0,1}em\>/g, "*").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&").replace(/&quot;/g, '"').replace(/&apos;/g, "'");
        return "<span id=\"latexid" + ++count + "\">...</span><script>katex.render(\"" + lstr + "\", latexid" + count + ", {displayMode:" + (sidx==2).toString() + ', macros:{"\\\\RR": "\\\\mathbb{R}", "\\\\f":"f(#1)"}});</' + "script>";
    });
}

var article_content = render(article_html)
$("article").html(article_content);
```

然后后端只需要实现类似于文档管理工具即可，依据需求实时生成`JSON`文档即可，在类似于主页或者归档的页面时，就可以类似于解析`MarkDown`一样采用`XHR`获取相应的`JSON`文档并解析显示到页面上，所以只需要很少的后端服务功能即可。基于此，当时还要想着使用之前买的但一直在吃灰的Linux开发板[FirePrime][FirePrime]作为服务器：

![FirePrime四核卡片电脑开源平台][FirePrimeHw]

然后域名解析方面使用[花生壳][OrayHSK]提供的内网动态域名解析服务：

![花生棒][OrayHSB]

现在想想还是太麻烦了，对于我这样的WEB菜鸟，采用`Jekyll + Github`已经完全足够了。

### 四、定制化博客
#### 1、参考文档
待定
#### 2、配置主题
待定

[jekyll-docs]: https://jekyllrb.com/docs/home
[jekyll-gh]:   https://github.com/jekyll/jekyll
[jekyll-talk]: https://talk.jekyllrb.com/
[minima]: https://github.com/jekyll/minima

[jekyllrb]: https://jekyllrb.com/
[jekyll-cn-site]: https://www.jekyll.com.cn/
[MarkDown]: http://www.markdown.cn/
[Strapdown.js]: http://strapdownjs.com/
[Katex.js]: https://katex.org/
[OldBlogArch]: /images/abandoned_blog_architecture.png
[FirePrime]: http://www.t-firefly.com/product/prime.html
[FirePrimeHw]: http://www.t-firefly.com/themes/t-firefly/public/assets/images/prime/01.jpg
[OrayHSK]: http://hsk.oray.com/
[OrayHSB]: http://static.orayimg.com/peanuthull/img/device_04_141215.jpg
