---
layout: post
title:  "常用GIT命令记录"
date:   2020-12-23 9:33:20 +0800
categories: notes
description: "日常中常用GIT命令的记录"
author: zburid
tags:   Git
typora-root-url: ..
show:   true
---

## 一、常用案例

#### 1. fatal: refusing to merge unrelated histories解决

把本地仓库和远程仓库关联以后，执行`git pull`出现该问题

```bash
$ git pull origin master --allow-unrelated-histories
```


#### 2. 使用远程仓库最新状态覆盖本地仓库

```bash
$ git fetch --all
$ git reset \--hard origin/master
$ git pull
```

#### 3. 某个分支的部分提交合并到当前分支

```bash
$ git cherry-pick <hashcode>
```

#### 4. 查看已经Add的文件的修改差异

```bash
$ git diff --cached
```

#### 5. 查看远程仓库提交日志

```bash
$ git log origin/master -n 3
```

#### 6. 查看最近两次提交之间涉及到修改的文件

```bash
$ git diff HEAD HEAD^ --stat
```

#### 7. 强行恢复远程代码到某个版本

```bash
$ git reset <hash code> --hard  # 恢复本地到某个版本
$ git push -f                   # 强制远程仓库恢复到本地当前版本
```

#### 8. 配置默认用户名和邮箱

```bash
$ git config --global user.name "XXXXX"
$ git config --global user.email "XXXXX@YYY.com"
```



## 二、远程仓库 `git remote`

```bash
$ git remote -v                                 # 查看远程仓库地址
origin	ssh://root@192.168.1.xx:xxxx/home/share/GitRepository/imx8_10_2.3.0.git (fetch)
origin	ssh://root@192.168.1.xx:xxxx/home/share/GitRepository/imx8_10_2.3.0.git (push)
$ git remote add origin <remote repository url> # 给本地仓库添加远程仓库地址
```

## 三、生成patch文件 `git format-patch`

```bash
$ git format-patch HEAD^        # 生成最近的1次commit的patch
$ git format-patch HEAD^^       # 生成最近的2次commit的patch
$ git format-patch HEAD^^^      # 生成最近的3次commit的patch
$ git format-patch HEAD^^^^     # 生成最近的4次commit的patch
$ git format-patch <r1>..<r2>   # 生成两个commit间的修改的patch（包含两个commit. <r1>和<r2>都是具体的commit号)
$ git format-patch -1 <r1>      # 生成单个commit的patch
$ git format-patch <r1>         # 生成某commit以来的修改patch（不包含该commit）
$ git format-patch --root <r1>  # 生成从根到r1提交的所有patch
```

## 四、打patch文件 `git am`

```bash
$ git apply --stat 0001-limit-log-function.patch    # 查看patch的情况
$ git apply --check 0001-limit-log-function.patch   # 检查patch是否能够打上，如果没有任何输出，则说明无冲突，可以打上
$ git am 0001-limit-log-function.patch              # 将名字为0001-limit-log-function.patch的patch打上
$ git am --signoff 0001-limit-log-function.patch    # 添加-s或者--signoff，还可以把自己的名字添加为signed off by信息，作用是注明打patch的人是谁，因为有时打patch的人并不是patch的作者
$ git am ~/patch-set/\*.patch                       # 将路径~/patch-set/\*.patch 按照先后顺序打上
$ git am --abort                                    # 当git am失败时，用以将已经在am过程中打上的patch废弃掉(比如有三个patch，打到第三个patch时有冲突，那么这条命令会把打上的前两个patch丢弃掉，返回没有打patch的状态)
$ git am --resolved                                 # 当git am失败，解决完冲突后，这条命令会接着打patch
```

`git apply`是另外一种打 patch 的命令，其与`git am`的区别是，`git apply`并不会将 commit message 等打上去，打完 patch 后需要重新`git add`和`git commit`，而`git am`会直接将 patch 的所有信息打上去，而且不用重新`git add`和`git commit`，author 也是 patch 的 author 而不是打 patch 的人。

`git am`和`git apply`的输入也不一样，`git am`接受的是 email 形式的提交或者`git format-patch`生成的 patch ，而`git apply`接受的是`git diff`生成的 diff 文件。

## 五、版本分支 `git branch`

```bash
$ git branch                    # 列出所有分支
$ git branch newbranch          # 创建分支
$ git checkout newbranch        # 切换分支
$ git checkout -b newbranch [r] # 创建并切换分支

$ git branch -d newbranch       # 删除分支
$ git branch -D newbranch       # 强制删除分支

$ git branch -v                 # 查看各个分支最后一次提交
$ git branch –merged            # 查看哪些分支合并入当前分支
$ git branch –no-merged         # 查看哪些分支未合并入当前分支

$ git rebase xxxxx              # 更新xxxxx分支上的东西到当前分支上
$ git merge xxxxx               # 合并xxxxx分支上的东西到当前分支上
$ git push origin newbranch     # 推送分支
```

## 六、修改提交 `git commit`

```bash
$ git commit -m "xxxxx"         # 提交并记录日志
$ git reset HEAD^               # 撤销最近一次提交(即退回到上一次版本)并本地保留代码
```

