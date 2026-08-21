# DeepSeek Harness (DSH) 内网部署指南 — 先测试后生产

> 版本：0.1.0-rc.7 | 协议：MIT  
> 适用环境：完全物理隔离内网 | **先测试后生产部署** | 虚拟化服务器(Ubuntu 20.04.6 LTS 测试环境 → RHEL 8.9 生产环境) | 算力服务器(鲲鹏920+昇腾910B) 运行 vLLM Ascend

---

## 目录

1. [部署流程概述](#1-部署流程概述)
2. [你的架构概况](#2-你的架构概况)
3. [前提条件](#3-前提条件)
4. [第一步：构建阶段（有网电脑，仅需做一次）](#4-第一步构建阶段有网电脑仅需做一次)
5. [第二步：测试环境部署 (Ubuntu 20.04.6 LTS) — 小白一步一步操作](#5-第二步测试环境部署-ubuntu-20046-lts--小白一步一步操作)
6. [第三步：配置模型](#6-第三步配置模型)
7. [第四步：验证与日常运维](#7-第四步验证与日常运维)
8. [第五步：生产环境部署 (RHEL 8.9)](#8-第五步生产环境部署-rhel-89)
9. [如果虚拟化服务器还没有 Docker](#9-如果虚拟化服务器还没有-docker)
10. [配置算力服务器的 vLLM Ascend 模型](#10-配置算力服务器的-vllm-ascend-模型)
11. [日常运维命令大全](#11-日常运维命令大全)
12. [常见问题](#12-常见问题)
13. [文件清单](#13-文件清单)

---

## 1. 部署流程概述

我们采用 **先测试后生产** 的规范流程：

```
有网电脑 → bash build-dsh-image.sh → 构建新版 Debian glibc 镜像
       ↓
有网电脑 → bash pack-and-send.sh → 打包分卷（约 12 个分卷）
       ↓
QQ 邮箱 → 发送全部 12 封附件 → 内网服务器
       ↓
测试环境 → Ubuntu 20.04 → 先在此部署测试 → 验证功能正常
       ↓
生产环境 → RHEL 8.9 → 一模一样的流程 → 投产
```

> **镜像已通过 GitHub Actions 自动构建完成。** 基于 Debian glibc 的新版镜像已包含在 `dsh-offline-image.tar.gz` 中，直接使用即可，无需重新构建。

关键优势：
- ✅ 先在测试环境跑通，验证没问题再上生产
- ✅ 测试环境和生产环境的算力服务器配置 **一模一样**，不会因为环境差异出问题
- ✅ 每一步都有详细命令，复制粘贴即可

---

## 2. 你的架构概况

已确认的硬件与软件环境：

| 环境 | 位置 | 服务器 | 角色 | 详情 |
|------|------|--------|------|------|
| **测试环境** | 虚拟化服务器 | 通用 x86 服务器 | 运行 DSH Web UI + Agent 引擎 | Ubuntu 20.04.6 LTS (Linux 5.4.0-216-generic)，Docker 容器化部署 |
| **生产环境** | 虚拟化服务器 | 通用 x86 服务器 | 运行 DSH Web UI + Agent 引擎 | Red Hat 8.9，Docker 容器化部署 |
| **算力服务器** | 通用 | 华鲲 AT3500 G3-792 | 运行模型推理 | 鲲鹏920(ARM) + 昇腾910B × 16卡 |
| **网络关系** | - | 内网互通 | DSH 通过 HTTP 调用 vLLM API | 内网 IP 可达 |

### 测试环境已部署的模型（vLLM Ascend）：

| 模型 | 用途 | DSH 中如何使用 |
|------|------|--------------|
| **DeepSeek-R1-Distill-Llama-70B** | Agent 主模型 — 推理、思考、规划 | 默认 Agent 模型 |
| **Qwen3-32B** | 通用对话模型 — 聊天问答 | 辅助对话 |
| **Qwen3-VL-30B-A3B-Instruct** | 多模态 — 图片理解、视觉问答 | 图片分析任务 |

### 生产环境已部署的模型（vLLM Ascend）：

| 模型 | 用途 | DSH 中如何使用 |
|------|------|--------------|
| **DeepSeek-V4-Flash-w8a8-mtp** | Agent 主模型 — 代码生成、推理、对话 | 默认 Agent 模型 |
| **Qwen3-VL-30B-A3B-Instruct** | 多模态 — 图片理解、视觉问答 | 图片分析任务 |
| **PaddleOCR-VL-0.9B** | OCR 文字识别 | 文档/图片文字提取 |
| **Qwen3-VL-Embedding-8B** | 向量嵌入 — 语义检索 | RAG 知识库检索 |
| **Qwen3-VL-Reranker-8B** | 重排序 — 搜索结果精排 | RAG 结果精排 |

**关键结论：算力已经有了，你只需要搭建 DSH 即可。**

---

## 3. 前提条件

### 3.1 准备工作（你需要提前准备）

| 位置 | 需要准备什么 |
|------|-------------|
| **邮箱** | 已收到全部 12 封邮件附件，按说明合并分卷 |
| **U盘/移动硬盘** | 至少 10GB 可用空间，格式化为 ext4 或 FAT32（用于传输到内网服务器） |
| **测试环境虚拟化服务器** | Ubuntu 20.04.6，已安装 Docker 或准备离线安装，至少 4GB 内存，2核+ |
| **生产环境虚拟化服务器** | RHEL 8.9，已安装 Docker 或准备离线安装，至少 4GB 内存，2核+ |
| **算力服务器** | 华鲲 AT3500 G3-792，已运行 vLLM Ascend，确认内网 IP 可达 |

> **注意：** Docker 镜像已提前构建好（约 518MB，基于 Debian glibc），包含在邮件分卷中，合并后直接使用。**你不需要在有网电脑上重新构建。**

### 3.2 确认网络连通性（**必须先做**）

在 **测试环境虚拟化服务器** 上执行以下命令，确认能访问算力服务器的 vLLM API：

```bash
# 1. 检查磁盘空间（看看当前目录所在分区够不够放镜像）
df -h
# 输出示例：
# Filesystem      Size  Used Avail Use% Mounted on
# udev            7.7G     0  7.7G   0% /dev
# tmpfs           1.6G  2.1M  1.6G   1% /run
# /dev/sda1       200G   50G  150G  25% /          ← 根分区有 150G 可用
# /dev/sdb1       500G  100G  400G  20% /data      ← /data 有 400G 可用
# 找一个可用空间大于 10GB 的分区，cd 到那个分区下操作

# 2. 检查 U 盘设备（插入 U 盘后执行）
lsblk
# 输出示例：
# NAME   MAJ:MIN RM   SIZE RO TYPE MOUNTPOINT
# sda      8:0    0   200G  0 disk
# ├─sda1   8:1    0   200G  0 part /
# sdb      8:16   1    16G  0 disk                ← 这就是你的 U 盘
# └─sdb1   8:17   1    16G  0 part /media/usb     ← 设备分区是 /dev/sdb1

# 3. 测试网络连通性（替换为你的算力服务器实际 IP）
curl -s http://<算力服务器IP>:8000/v1/models
```

**预期结果：** 应该返回 JSON 格式的模型列表，类似这样：
```json
{
  "object": "list",
  "data": [
    {"id": "DeepSeek-R1-Distill-Llama-70B", ...},
    {"id": "Qwen3-32B", ...},
    {"id": "Qwen3-VL-30B-A3B-Instruct", ...}
  ]
}
```

如果能返回，说明网络没问题，可以继续。

如果无法访问，请检查：
- 两台服务器的网络是否互通（用 `ping <算力服务器IP>` 测试）
- 算力服务器防火墙是否开放了 8000 端口
- vLLM Ascend 服务是否正常运行

---

## 4. 第一步：合并邮件分卷，准备部署包

### 4.1 下载全部邮件附件

你已收到 12 封邮件，请全部下载附件到同一个目录（例如 `~/dsh-email`）：

| 邮件 | 附件 | 大小 | 说明 |
|------|------|------|------|
| 1/12 | `01-dsh-config-files.zip` | ~30MB | 配置脚本 + 源码 + Node.js |
| 2-10/12 | `dsh-image-part-00` ~ `08` | 9 × 45MB | Docker 镜像分卷 |
| 11-12/12 | `pnpm-part-00` ~ `01` | 45MB + 19MB | pnpm 包管理器分卷 |

### 4.2 合并分卷

```bash
# 1. 创建目录，把所有附件放进去
mkdir -p ~/dsh-email
cd ~/dsh-email

# 2. 确认所有文件已下载
ls -la
# 应该看到 12 个文件

# 3. 合并 Docker 镜像分卷
cat dsh-image-part-* > dsh-offline-image.tar.gz

# 4. 合并 pnpm 分卷
cat pnpm-part-* > pnpm-linux-x64

# 5. 解压配置文件包
unzip 01-dsh-config-files.zip -d dsh-deploy

# 6. 验证 MD5 校验（确认文件完整）
md5sum dsh-offline-image.tar.gz pnpm-linux-x64

# 7. 将合并后的大文件放入配置目录
mv dsh-offline-image.tar.gz pnpm-linux-x64 dsh-deploy/
cd dsh-deploy
ls -la
# 确认所有文件就绪
```

### 4.3 复制到 U 盘

```bash
# 插入 U 盘，查看 U 盘设备
lsblk
# 找到你的 U 盘设备，通常是 /dev/sdb1 或 /dev/sdc1

# 挂载 U 盘
sudo mkdir -p /mnt/usb
sudo mount /dev/sdb1 /mnt/usb

# 复制整个部署包到 U 盘
sudo cp -r ~/dsh-email/dsh-deploy /mnt/usb/

# 同步缓冲区（重要！不要直接拔 U 盘）
sync
sudo umount /mnt/usb
```

现在拔出 U 盘，插到测试环境服务器。

---

## 5. 第二步：测试环境部署 (Ubuntu 20.04.6 LTS) — 小白一步一步操作

### 5.1 查看磁盘空间，找位置落盘

**第一步：** 登录到测试环境 Ubuntu 20.04 服务器（通过 SSH 或直接操作）。

```bash
# 1. 查看当前各个分区的可用空间
df -h
# 看懂输出：
#   Filesystem      Size  Used Avail Use% Mounted on
#   /dev/sda1       200G   50G  150G  25% /          ← 根分区 / 有 150G 可用
#   /dev/sdb1       500G  100G  400G  20% /data      ← /data 分区有 400G 可用
#
# 输出的最后一列是"挂载点"(Mounted on)，表示这个分区在哪个目录下
# 找一个 可用空间(Avail) 大于 10GB 的分区，cd 到那个挂载点

# 2. 假设 /data 分区空间够大，就切换到 /data
cd /data
# 如果你的根分区 / 空间够大，也可以直接用用户目录
cd ~
```

### 5.2 插入 U 盘，查看设备

```bash
# 插入 U 盘后，执行以下命令查看 U 盘设备
lsblk
# 输出示例：
# NAME   MAJ:MIN RM   SIZE RO TYPE MOUNTPOINT
# sda      8:0    0   200G  0 disk
# ├─sda1   8:1    0   200G  0 part /
# sdb      8:16   1    16G  0 disk                ← 新出现的设备，就是 U 盘
# └─sdb1   8:17   1    16G  0 part                ← U 盘分区，设备名是 /dev/sdb1
#
# 如果 sdb 下面没有 sdb1，说明 U 盘没有分区，可能是 /dev/sdb 本身
# 注意：sda 是系统硬盘，sdb 是新插入的 U 盘，以此类推
```

### 5.3 挂载 U 盘，复制文件

```bash
# 1. 创建挂载点目录（如果已经存在就跳过）
sudo mkdir -p /mnt/usb

# 2. 挂载 U 盘（把 /dev/sdb1 替换为你实际看到的设备名）
sudo mount /dev/sdb1 /mnt/usb

# 3. 验证挂载成功
ls -la /mnt/usb/
# 应该看到类似这样的输出：
# drwxr-xr-x  3 root root  4096 ... dsh-usb-bundle/  ← 这个目录就是交付包
# drwxr-xr-x  2 root root  4096 ... docker-offline-pkg/  ← 如果有准备 Docker 离线包

# 4. 复制到当前目录（你刚才选的落盘位置，比如 /data）
sudo cp -r /mnt/usb/dsh-usb-bundle ./
# 如果没有准备 Docker 离线包，这步可以跳过
# 如果 U 盘里有 docker-offline-pkg，也复制过来备用
sudo cp -r /mnt/usb/docker-offline-pkg ./ 2>/dev/null || true

# 5. 进入部署包目录
cd dsh-deploy

# 6. 查看内容确认
ls -la
# 应该看到：
#   dsh-offline-image.tar.gz  ← DSH Docker 镜像（核心文件，约 403MB）← 稍后要移入配置目录
#   pnpm-linux-x64            ← pnpm 包管理器（离线安装用，约 64MB）
#   01-dsh-config-files       ← 解压出的配置目录（下面有 docker-compose.yml 等）

# 7. 将镜像和 pnpm 移入配置目录（deploy.sh 需要它们在同一目录下）
mv dsh-offline-image.tar.gz pnpm-linux-x64 01-dsh-config-files/
cd 01-dsh-config-files
ls -la
# 应该看到：
#   dsh-offline-image.tar.gz      ← DSH Docker 镜像（核心文件，约 403MB）
#   pnpm-linux-x64                ← pnpm 包管理器（离线安装用，约 64MB）
#   Dockerfile                    ← 镜像构建文件
#   docker-compose.yml            ← 容器编排配置
#   settings.yaml                 ← 模型配置模板
#   deploy.sh                     ← 一键部署脚本
#   README.md                     ← 本指南
#   docker-entrypoint.sh          ← 容器入口脚本
#   build-and-save.sh             ← 镜像构建脚本
#   prepare-docker-offline.sh     ← Docker 离线安装包准备脚本
#   node-v22.19.0-linux-x64.tar.xz ← Node.js 22 运行时
#   deepseek-ai-dsh-0.1.0-rc.7.tgz ← DSH 源码包

# 8. 确认完 U 盘不再需要后，可以卸载
cd /
sudo umount /mnt/usb
# 现在可以拔掉 U 盘了
```

### 5.4 检查 Docker 是否已安装

```bash
# 检查 Docker 命令是否存在
docker --version
# 如果输出版本号，说明已安装，跳到下一步（5.5）
# 例如：Docker version 24.0.7, build afdd53b

# 如果提示 "command not found: docker"，说明没装 Docker
# 请跳到第 9 章【如果虚拟化服务器还没有 Docker】先安装 Docker
```

### 5.5 检查磁盘空间是否足够加载镜像

```bash
# 查看当前目录所在分区的可用空间
df -h .
# 确保可用空间大于 2GB（镜像加载和解压需要空间）
# 如果空间不足，清理磁盘或换到更大分区的目录

# 查看镜像文件大小，确认文件完整
# 注意：deploy.sh 脚本在 dsh-deploy/ 目录下查找 dsh-offline-image.tar.gz
# 所以需要先回到 dsh-deploy 目录，再把镜像和配置文件放一起
cd /path/to/dsh-deploy   # 替换为实际路径
ls -lh dsh-offline-image.tar.gz
# 输出类似：-rw-r--r-- 1 root root 403M ... dsh-offline-image.tar.gz
# 大小应该在 400MB~500MB 左右，如果太小说明文件可能损坏
```

### 5.6 一键部署

> **前提：** 确保你已经在 `01-dsh-config-files` 目录下（上面第 7 步已经 `cd 01-dsh-config-files`），并且 `dsh-offline-image.tar.gz` 和 `deploy.sh` 在同一目录下。

```bash
# 1. 赋予执行权限（如果还没赋权）
chmod +x deploy.sh

# 2. 执行部署脚本
./deploy.sh
```

**部署脚本会做的事情：**

**第 1 步：** 脚本会检测操作系统，显示当前系统信息。

**第 2 步：** 脚本会问你要部署到哪个环境：
```
请选择部署环境：
  1) 测试环境（Ubuntu 20.04）— 推荐先在此部署测试
  2) 生产环境（RHEL 8.9）
请输入选项 (1/2):
```
输入 **1** 然后按回车。

**第 3 步：** 脚本检查 Docker 是否正常运行。

**第 4 步：** 脚本自动检测镜像文件格式并加载（支持 gzip / xz / 纯 tar / bzip2，无需手动操心）。
```
📦 检测文件格式: dsh-offline-image.tar.gz...
    检测结果: POSIX tar archive
    ✅ 检测为纯 tar 格式（未压缩），直接加载...
    执行命令: docker load -i "dsh-offline-image.tar.gz"
    加载输出: Loaded image: localhost/dsh-offline:latest
    ✅ 实际镜像名: localhost/dsh-offline:latest
    🔧 镜像名与标准名不一致，添加 tag 别名: dsh-offline:latest
    ✅ 别名添加完成
```
会看到 Docker 输出加载进度，最终显示 `Loaded image: localhost/dsh-offline:latest` 并自动补上 `dsh-offline:latest` 别名。

**第 5 步：** 脚本创建 `workspace/` 和 `dsh-home/` 目录，并复制 `settings.yaml` 配置模板。

**第 6 步：** ⚠️ **脚本会暂停，提示你编辑配置文件**：
```
⚠️  重要：请编辑 dsh-home/settings.yaml
   将 <测试环境算力服务器IP> 替换为测试环境算力服务器的实际内网 IP
```

**此时不要按回车**，先打开另一个终端窗口（或者按 Ctrl+Z 暂停脚本，编辑完再 `fg` 恢复），执行以下命令编辑配置：

```bash
# 编辑配置文件（用 vim 或 nano 都可以）
vim dsh-home/settings.yaml
# 或者
nano dsh-home/settings.yaml
```

找到文件中的以下行，把 `<测试环境算力服务器IP>` 替换为实际 IP：

```yaml
# 修改前：
baseURL: "http://<测试环境算力服务器IP>:8000/v1"

# 修改后（示例，替换为你的实际 IP）：
baseURL: "http://192.168.1.100:8000/v1"
```

**需要替换的地方有 3 处**（DeepSeek、Qwen3、Qwen3-VL 三个模型配置），全部替换完后保存退出：
- vim 保存退出：按 `Esc`，输入 `:wq`，按回车
- nano 保存退出：按 `Ctrl+X`，按 `Y`，按回车

**第 6 步：** 脚本自动启动容器，使用 `--network host` 模式（绕开 iptables 端口映射问题）。容器内部：
- **DSH 绑定 `127.0.0.1:3080`**（DSH 安全策略限制，只允许本地回环地址）
- **Node.js TCP 转发 `0.0.0.0:3080 → 127.0.0.1:3080`**（让外部网络可以访问，不需要额外安装任何包）
```
📡 服务器 IP: 192.168.1.100
   容器使用 host 网络模式
   DSH 绑定 127.0.0.1（安全策略限制）
   Node.js 转发 0.0.0.0:3080 → 127.0.0.1:3080

📋 使用 Docker Compose 启动...
```
或者使用 `docker run` 方式：
```
📋 使用 docker run 启动（--network host 模式）...
```

**第 8 步：** 看到以下输出说明部署成功：
```
✅ 启动成功！
   访问地址: http://192.168.1.100:3080
```

> **注意：** 使用 host 网络模式后，容器直接绑定到服务器 IP，不需要额外配置防火墙端口转发。如果仍需限制访问，请在服务器防火墙中放行 3080 端口。

### 5.7 开放防火墙端口（Ubuntu 使用 ufw）

Ubuntu 20.04 默认可能没有开启防火墙，但如果开启了 ufw，需要开放 3080 端口：

```bash
# 查看防火墙状态
sudo ufw status
# 输出示例：
# Status: inactive    ← 防火墙没开，不需要操作
# 或
# Status: active      ← 防火墙开了，需要开放端口
# 3080/tcp ALLOW Anywhere    ← 已经开放了，不需要操作

# 如果防火墙已开启但没有 3080 端口，执行：
sudo ufw allow 3080/tcp

# 再次确认
sudo ufw status
```

---

## 6. 第三步：配置模型

### 6.1 确认模型配置

`settings.yaml` 已经预先填好所有测试环境模型配置。如果你在 5.6 节已经替换了 IP，现在可以跳过编辑步骤。

如果需要重新编辑：

```bash
# 编辑配置
vim dsh-home/settings.yaml
# 或
nano dsh-home/settings.yaml
```

**确保以下内容正确：**

1. `test-ascend-deepseek` 的 baseURL 指向测试环境算力服务器
2. `test-ascend-qwen` 的 baseURL 指向同一个 IP
3. `test-ascend-qwen-vl` 的 baseURL 指向同一个 IP
4. 默认模型使用 `test-ascend-deepseek` / `DeepSeek-R1-Distill-Llama-70B`

编辑完成后，重启容器生效：

```bash
docker restart dsh
```

### 6.2 通过 Web UI 配置（备选方案）

如果不想编辑配置文件，也可以通过 Web UI 配置：

1. 浏览器访问 `http://<服务器IP>:3080`
2. 点击 **设置 → 模型**
3. 点击 **添加自定义提供方**，添加以下配置：

**第一个提供方（Agent 主模型）：**
| 字段 | 值 |
|------|------|
| Provider ID | `test-ascend-deepseek` |
| 基础 URL | `http://<测试环境算力服务器IP>:8000/v1` |
| API 协议 | `openai-completions` |
| API 密钥 | 留空 |
| 模型列表 | `DeepSeek-R1-Distill-Llama-70B` |

**第二个提供方（通用对话）：**
| 字段 | 值 |
|------|------|
| Provider ID | `test-ascend-qwen` |
| 基础 URL | `http://<测试环境算力服务器IP>:8000/v1` |
| API 协议 | `openai-completions` |
| API 密钥 | 留空 |
| 模型列表 | `Qwen3-32B` |

**第三个提供方（多模态）：**
| 字段 | 值 |
|------|------|
| Provider ID | `test-ascend-qwen-vl` |
| 基础 URL | `http://<测试环境算力服务器IP>:8000/v1` |
| API 协议 | `openai-completions` |
| API 密钥 | 留空 |
| 模型列表 | `Qwen3-VL-30B-A3B-Instruct` |

---

## 7. 第四步：验证与日常运维

### 7.1 验证容器状态

```bash
# 查看所有容器（包括运行中和已停止的）
docker ps -a | grep dsh

# 应该看到类似这样（STATUS 是 Up 表示正在运行）：
# CONTAINER ID   IMAGE               COMMAND                  STATUS       PORTS                    NAMES
# abc123def456   dsh-offline:latest  "docker-entrypoint.…"   Up 2 hours   0.0.0.0:3080->3080/tcp   dsh

# 如果容器没有在运行，查看日志排查问题
docker logs dsh
```

### 7.2 查看启动日志

```bash
# 查看所有历史日志（启动时的日志都在这里）
docker logs dsh

# 实时跟踪日志输出（按 Ctrl+C 退出跟踪）
docker logs -f dsh

# 查看最近的 50 行日志
docker logs dsh --tail 50

# 查看日志并加上时间戳
docker logs dsh -t

# 如果容器启动失败，查看详细错误
docker logs dsh 2>&1 | tail -50
```

### 7.3 首次访问 Web UI

1. 打开浏览器，访问：`http://<测试环境服务器IP>:3080`
   - 如果本地浏览器无法访问，请确认网络路由
   - 如果是 SSH 连接服务器，可以用 SSH 端口转发：`ssh -L 3080:localhost:3080 <服务器IP>`，然后访问 `http://localhost:3080`

2. 看到 DSH 登录界面 → 说明部署成功！

### 7.4 验证模型配置

1. 点击 **设置 → 模型**
2. 你应该能看到三个模型已经配置好：
   - `test-ascend-deepseek` → DeepSeek-R1-Distill-Llama-70B
   - `test-ascend-qwen` → Qwen3-32B
   - `test-ascend-qwen-vl` → Qwen3-VL-30B-A3B-Instruct
3. 在模型列表中，确认 `DeepSeek-R1-Distill-Llama-70B` 已经被选为默认模型

### 7.5 测试一个简单对话

1. 点击左侧 **+ 新建工作区**
2. 输入一个简单问题：`你好，请介绍一下你自己`
3. 点击发送，等待回复

如果模型正常回复，**说明测试环境部署成功！** ✅

### 7.6 测试多模态图片理解

1. 在对话框中，点击图片上传按钮，上传一张图片
2. 输入问题：`描述一下这张图片的内容`
3. 发送，Agent 会调用 Qwen3-VL 模型回答

如果正常回复，说明多模态也没问题。

---

## 8. 第五步：生产环境部署 (RHEL 8.9)

当测试环境验证完全正常后，就可以部署到生产环境。流程和测试环境**一模一样**，只有操作系统细节不同。

### 8.1 查看磁盘空间，挂载 U 盘

```bash
# 1. 查看磁盘空间
df -h
# 找一个大于 10GB 可用空间的分区，cd 进去

# 2. 插入 U 盘，查看设备
lsblk
# 找到 U 盘设备，通常是 /dev/sdb1

# 3. 挂载
sudo mkdir -p /mnt/usb
sudo mount /dev/sdb1 /mnt/usb

# 4. 复制到本地（dsh-deploy 是合并后的完整目录）
sudo cp -r /mnt/usb/dsh-deploy ./
cd dsh-deploy/01-dsh-config-files
ls -la
# 确认 dsh-offline-image.tar.gz 和 deploy.sh 都在当前目录
```

### 8.2 一键部署（RHEL 8.9）

```bash
# 赋权
chmod +x deploy.sh

# 执行部署，选择选项 2（生产环境）
./deploy.sh
```

**注意：** 同样，脚本会暂停让你编辑 `settings.yaml`，记得：
1. 将 `<生产环境算力服务器IP>` 替换为生产环境算力服务器实际内网 IP
2. 将默认模型改为生产环境的主模型：
   ```yaml
   agent-default-model:
     provider: prod-ascend-deepseek
     model: DeepSeek-V4-Flash-w8a8-mtp
   ```

### 8.3 开放防火墙（RHEL 8.9 使用 firewalld）

```bash
# 开放 3080 端口
sudo firewall-cmd --add-port=3080/tcp --permanent
sudo firewall-cmd --reload
# 检查是否开放成功
sudo firewall-cmd --list-ports
# 应该看到：3080/tcp
```

### 8.4 验证和运维，和测试环境完全一样

验证步骤和测试环境完全相同：
```bash
# 查看容器状态
docker ps -a | grep dsh

# 查看日志
docker logs -f dsh

# 浏览器访问 http://<生产环境服务器IP>:3080
# 验证功能正常 → 投产完成！
```

---

## 9. 如果虚拟化服务器还没有 Docker

### 测试环境（Ubuntu 20.04）离线安装 Docker：

**在 有网电脑 上执行：**
```bash
./prepare-docker-offline.sh
# 选择选项 3 → Ubuntu → 选择选项 1 → 20.04 (focal)
# 脚本会自动下载所有 deb 包到 docker-offline-pkg/
# 把 docker-offline-pkg/ 目录复制到 U 盘
```

**在 测试环境服务器 上执行：**
```bash
# 1. 挂载 U 盘
sudo mkdir -p /mnt/usb
sudo mount /dev/sdb1 /mnt/usb

# 2. 复制 Docker 离线包到本地
cp -r /mnt/usb/docker-offline-pkg ~/
cd ~/docker-offline-pkg

# 3. 查看 deb 包列表
ls -la *.deb
# 应该看到类似：
# containerd.io_1.6.28-1_amd64.deb
# docker-ce_24.0.7-1~ubuntu.20.04~focal_amd64.deb
# docker-ce-cli_24.0.7-1~ubuntu.20.04~focal_amd64.deb
# docker-buildx-plugin_0.12.1-1~ubuntu.20.04~focal_amd64.deb
# docker-compose-plugin_2.24.0-1~ubuntu.20.04~focal_amd64.deb

# 4. 安装所有 deb 包
sudo dpkg -i *.deb
# 如果报依赖缺失错误，执行：
sudo apt-get update
sudo apt-get install -f
sudo dpkg -i *.deb

# 5. 启动 Docker 服务
sudo systemctl start docker
sudo systemctl enable docker

# 6. 验证安装
docker --version
# 应该输出：Docker version 24.0.7, build afdd53b

# 7. 验证 Docker 正常运行
sudo docker run hello-world 2>/dev/null || echo "内网无法拉取 hello-world 镜像，跳过"
# 因为内网无法联网，会报错，这是正常的
# 跳过即可，用 docker info 验证：
docker info | head -10
```

### 生产环境（RHEL 8.9）离线安装 Docker：

**在 有网电脑 上执行：**
```bash
./prepare-docker-offline.sh
# 选择选项 1 → RHEL 8.9 / CentOS 8
# 脚本下载 RPM 包 → 复制到 U 盘
```

**在 生产环境服务器 上执行：**
```bash
# 1. 挂载 U 盘
sudo mount /dev/sdb1 /mnt/usb
cp -r /mnt/usb/docker-offline-pkg ~/
cd ~/docker-offline-pkg

# 2. 安装 RPM 包
sudo rpm -ivh *.rpm
# 如果提示依赖缺失：
sudo yum install -y yum-utils device-mapper-persistent-data lvm2
# 重新安装
sudo rpm -ivh *.rpm

# 3. 启动 Docker
sudo systemctl start docker
sudo systemctl enable docker

# 4. 验证
docker --version
docker info | head -10
```

---

## 10. 配置算力服务器的 vLLM Ascend 模型

### 10.1 确认算力服务器 vLLM 服务状态

在虚拟化服务器上先确认：

```bash
# 替换为实际 IP
curl http://<算力服务器IP>:8000/v1/models
```

如果返回模型列表，说明服务正常。

### 10.2 通过配置文件（settings.yaml）配置

`settings.yaml` 已经预先填好所有环境模型配置。你只需将 `<算力服务器IP>` 替换为实际 IP，然后重启容器：

```bash
# 编辑配置
vim dsh-home/settings.yaml
# 替换 IP 后保存

# 重启容器生效
docker restart dsh
```

### 10.3 选择默认模型

在 Web UI 的模型选择器中，选择对应的默认模型：

- **测试环境：** `DeepSeek-R1-Distill-Llama-70B`
- **生产环境：** `DeepSeek-V4-Flash-w8a8-mtp`

---

## 11. 日常运维命令大全

### 容器管理

```bash
# 查看容器状态
docker ps -a | grep dsh

# 查看实时日志（按 Ctrl+C 退出）
docker logs -f dsh

# 查看最近 100 行日志
docker logs dsh --tail 100

# 查看历史日志
docker logs dsh

# 重启容器（改了配置后需要）
docker restart dsh

# 停止容器
docker stop dsh

# 启动已停止的容器
docker start dsh

# 完全删除容器（要重新部署时用）
docker stop dsh
docker rm dsh

# 进入容器内部调试
docker exec -it dsh bash

# 查看容器资源占用（实时）
docker stats dsh

# 查看容器详细信息（IP、端口映射、挂载卷等）
docker inspect dsh
```

### 删除旧镜像并重新部署

如果需要更换或升级 DSH 镜像（例如从旧版 Alpine 镜像升级到新版 Debian glibc 镜像），按以下步骤操作：

> ⚠️ **注意：** 以下操作会删除旧容器和旧镜像，建议先备份 `dsh-home/` 和 `workspace/` 目录。

#### 标准流程（推荐）

```bash
# 1. 【可选】备份数据（以防万一）
cp -r dsh-home dsh-home.bak
cp -r workspace workspace.bak

# 2. 停止并删除旧容器
docker stop dsh 2>/dev/null
docker rm dsh 2>/dev/null

# 3. 查看所有镜像，找到旧版 DSH 镜像
docker images | grep dsh
# 输出示例：
# dsh-offline          latest        abc123def456   3 days ago     422MB
# localhost/dsh-offline latest      abc123def456   3 days ago     422MB
# <none>               <none>       def789abc123   3 days ago     422MB  ← dangling 镜像

# 4. 删除旧镜像
#    如果镜像 ID 被多个 tag 引用，先删除所有 tag 别名
docker rmi localhost/dsh-offline:latest 2>/dev/null
docker rmi dsh-offline:latest 2>/dev/null

# 5. 如果还有 dangling 镜像（<none>:<none>），一并清理
docker image prune -f

# 6. 确认旧镜像已被删除干净
docker images | grep dsh
# 应该没有任何输出，说明已删除干净

# 7. 加载新镜像
docker load -i dsh-offline-image.tar.gz

# 8. 重新部署
./deploy.sh
```

#### 强制删除（如果标准流程删不掉）

```bash
# 如果镜像被多个 tag 引用导致无法删除，可以用镜像 ID 强制删除
docker images | grep dsh
# 记下 IMAGE ID（例如 abc123def456）

# 强制删除
docker rmi -f abc123def456

# 清理 dangling 镜像
docker image prune -f
```

#### 彻底清理（包括所有数据）

> ⚠️ **警告：** 以下操作会删除所有 DSH 数据，包括配置、对话历史、工作区文件。**不可恢复！**

```bash
# 1. 停止并删除容器
docker stop dsh 2>/dev/null
docker rm dsh 2>/dev/null

# 2. 删除所有相关镜像
docker images | grep dsh | awk '{print $3}' | xargs -r docker rmi -f 2>/dev/null

# 3. 清理 dangling 镜像
docker image prune -f

# 4. 删除本地数据目录（可选，谨慎操作）
rm -rf dsh-home workspace

# 5. 确认全部清理干净
docker images | grep dsh
docker ps -a | grep dsh
ls -la dsh-home workspace 2>/dev/null || echo "已清空"
```

#### 从旧版 Alpine 镜像升级到新版 Debian glibc 镜像

旧版镜像（Alpine musl）的典型错误：
```
Error: Could not load the sharp module
Error: ld-linux-x86-64.so.2: no such file or directory
```

升级步骤：
```bash
# 1. 备份数据
cp -r dsh-home dsh-home.bak
cp -r workspace workspace.bak

# 2. 停止并删除旧容器
docker stop dsh && docker rm dsh

# 3. 删除旧 Alpine 镜像
docker rmi localhost/dsh-offline:latest 2>/dev/null
docker rmi dsh-offline:latest 2>/dev/null
docker image prune -f

# 4. 加载新 Debian 镜像
docker load -i dsh-offline-image.tar.gz

# 5. 重新部署
./deploy.sh
```

### 磁盘空间管理

```bash
# 查看整个 dsh-usb-bundle 目录占用多大
du -sh .

# 查看 Docker 占用的磁盘空间
docker system df

# 清理无用数据（已停止的容器、未使用的镜像、缓存等）
docker system prune -f

# 查看容器日志文件大小
ls -lh $(docker inspect --format='{{.LogPath}}' dsh) 2>/dev/null || echo "使用默认日志驱动"

# 如果日志太大，可以清理（谨慎操作，会丢失所有历史日志）
sudo truncate -s 0 $(docker inspect --format='{{.LogPath}}' dsh) 2>/dev/null || true
```

### 模型连接测试

```bash
# 从虚拟化服务器直接测试
curl http://<算力服务器IP>:8000/v1/models

# 从容器内部测试
docker exec dsh curl -s http://<算力服务器IP>:8000/v1/models | python3 -m json.tool 2>/dev/null || docker exec dsh curl -s http://<算力服务器IP>:8000/v1/models
```

### 数据持久化

所有数据都存在本地目录：

| 本地目录 | 容器内挂载点 | 用途 |
|---------|-------------|------|
| `./workspace` | `/workspace` | 工作区（存放代码项目） |
| `./dsh-home` | `/root/.dsh` | DSH 配置、会话日志、凭据 |

这些目录不会因为容器重启而丢失数据，放心使用。

---

## 12. 常见问题

#### ❌ 容器反复重启，日志报 `--host 0.0.0.0 is intentionally not supported yet`

```text
error: --host 0.0.0.0 is intentionally not supported yet for safety:
it would expose remote code execution to the network;
use 127.0.0.1 instead
```

**原因：** DSH 的 webserver 插件出于安全考虑，**硬编码禁止**绑定 `0.0.0.0`（所有网卡），只允许 `127.0.0.1`（本地回环）。

**解决方案：** 通过 Node.js TCP 端口转发（不需要额外安装任何包），DSH 绑定 `127.0.0.1`，Node.js 监听 `0.0.0.0` 并将流量转发到 DSH：
```
用户请求 → Node.js 转发(0.0.0.0:3080) → DSH(127.0.0.1:3080)
```

**修复：** 更新到最新版部署包（v7），`docker-entrypoint.sh` 已内置 Node.js 转发代码，无需重新构建镜像，替换文件后重启容器即可。

**手动修复（如果已在旧版容器中）：**
```bash
# 1. 停止旧容器
docker stop dsh
docker rm dsh

# 2. 确保 entrypoint 脚本有可执行权限（卷挂载需要）
chmod +x docker-entrypoint.sh

# 3. 重新创建容器（使用正确的 --host 127.0.0.1）
#    注意：docker-entrypoint.sh 已内置 Node.js 转发，需要挂载覆盖镜像里的旧版
docker run -d \
    --name dsh \
    --restart unless-stopped \
    --network host \
    -e DSH_ARGS="--host 127.0.0.1 --port 3080" \
    -v $(pwd)/workspace:/workspace \
    -v $(pwd)/dsh-home:/root/.dsh \
    -v $(pwd)/docker-entrypoint.sh:/usr/local/bin/docker-entrypoint.sh \
    dsh-offline:latest

# 4. 验证
docker ps | grep dsh
docker logs dsh --tail 20
```

#### ❌ 浏览器访问不了，ping 通但 telnet 不通

```text
ping 192.168.1.100   ✅ 通
telnet 192.168.1.100 3080 ❌ 不通
```

**原因：** 容器没启动（崩溃重启循环中），所以 3080 端口没监听。先检查容器状态：
```bash
docker ps -a | grep dsh
```
如果状态是 `Restarting`，说明容器在崩溃重启，按上一条 FAQ 修复后再试。

**如果容器状态是 `Up` 但 3080 不通：**
```bash
# 确认容器内确实在监听
sudo netstat -tlnp | grep 3080

# 或使用 ss 命令
sudo ss -tlnp | grep 3080
```

#### ❌ Gzip 格式错误

```text
gzip: xxx.tar.gz: not in gzip format
```

**原因：** 文件不是 gzip 压缩格式，但文件名带 `.tar.gz` 后缀。新版脚本（v2+）已自动检测格式，如果还遇到此问题，请确认已更新到最新版 `deploy.sh`。

**手动修复（如果确实遇到）：**
```bash
# 先用 file 命令查看实际格式
file dsh-offline-image.tar.gz

# 如果是纯 tar 格式，直接加载
docker load -i dsh-offline-image.tar.gz

# 或通过管道加载
cat dsh-offline-image.tar.gz | docker load
```

### Q1: 构建时 Docker 镜像要选什么架构？

**答：x86_64（amd64）。** 你的虚拟化服务器是通用 x86 架构，所以镜像构建时默认就是 `linux/amd64`。Dockerfile 已使用 `debian:bookworm-slim` 基础镜像，默认支持 x86_64，构建时无需额外参数。

### Q2: 算力服务器的 IP 怎么找？

**答：** 在虚拟化服务器上执行：

```bash
# 查看路由，找到默认网关，推测网段
ip route show
# 或者
route -n

# 如果知道算力服务器的主机名，用 ping 找 IP
ping <算力服务器的主机名>

# 如果没有主机名，需要问管理员
```

找到算力服务器的内网 IP（通常是 `10.x.x.x`、`172.x.x.x` 或 `192.168.x.x` 段），填入 `settings.yaml` 的 `baseURL` 中。

### Q3: 运行时报 "MISSING_CREDENTIAL" 错误？

**答：** 昇腾 vLLM 不校验 API Key，所以 `apiKeyEnv: ""` 是正确的。如果报这个错误，确认 `settings.yaml` 中配置的 `apiKeyEnv` 为空字符串或已删除该行。

### Q4: 运行时报 "UNKNOWN_MODEL" 错误？

**答：** 模型名称大小写不匹配。请通过 `curl http://<算力IP>:8000/v1/models` 获取准确的模型名称，**一字不差** 填入配置。

### Q5: DSH 支持多模态（图片输入）吗？

**答：** 支持。DSH 的 Web UI 支持上传图片，Agent 可以调用多模态模型（如 Qwen3-VL）进行图片理解。配置文件中已经为 Qwen3-VL 添加了 `input: [text, image]` 声明，开箱即用。

### Q6: DSH 需要占用多少资源？

**答：** DSH 本身（Agent 框架）消耗很小，建议分配 2-4GB 内存、2 核 CPU。真正的算力消耗在昇腾算力服务器上，与虚拟化服务器无关。

### Q7: 测试通过了，怎么迁生产？

**答：** 一模一样的流程：
1. 将整个 `dsh-deploy` 目录从 U 盘复制到生产环境服务器
2. `cd dsh-deploy/01-dsh-config-files` 进入配置目录
3. 编辑 `settings.yaml`，替换生产环境算力服务器 IP，修改默认模型
4. `./deploy.sh` 启动容器（选择选项 2 生产环境）
5. 验证功能 → 完成

### Q8: 容器启动了，但浏览器访问不了？

**答：** 按顺序检查：

```bash
# 1. 容器是否在运行
docker ps | grep dsh
# 确认 STATUS 是 Up

# 2. 端口是否监听
sudo netstat -tlnp | grep 3080
# 确认 0.0.0.0:3080 在 LISTEN 状态

# 3. 防火墙是否开放
# Ubuntu：
sudo ufw status
# RHEL：
sudo firewall-cmd --list-ports

# 4. 能不能从本机访问
curl http://localhost:3080
# 如果返回 HTML 内容，说明服务正常

# 5. 如果以上都正常，但远程浏览器无法访问
# 检查网络路由、VPN、是否在同一个网段
```

### Q9: 加载镜像时报 "no space left on device"？

**答：** 磁盘空间不足。找一个更大的分区重新操作：

```bash
# 查看各分区空间
df -h

# 切换到空间大的分区
cd /data  # 或者 /home 或其他

# 把 dsh-usb-bundle 重新复制过来
cp -r /mnt/usb/dsh-usb-bundle ./
cd dsh-usb-bundle
./deploy.sh
```

### Q10: 配置文件改错了怎么办？

**答：** 重新复制一份默认配置：

```bash
# 删除配错的配置文件
rm dsh-home/settings.yaml

# 重新从模板复制
cp settings.yaml dsh-home/settings.yaml

# 重新编辑
vim dsh-home/settings.yaml

# 重启容器
docker restart dsh
```

### Q11: 启动时报 YAML 解析错误 "invalid document at line 28, column 14"？

**答：** `settings.yaml` 中 `baseURL` 的值包含 `<` 和 `>` 符号，YAML 要求这类特殊字符必须用引号包裹。请编辑 `dsh-home/settings.yaml`，将所有 `baseURL` 的值用双引号包裹：

```yaml
# 错误写法（YAML 解析失败）：
baseURL: http://<算力服务器IP>:8000/v1

# 正确写法：
baseURL: "http://<算力服务器IP>:8000/v1"
```

如果已经填入了实际 IP，同样需要加引号：

```yaml
baseURL: "http://192.168.1.100:8000/v1"
```

修改后保存，重启容器即可。

### Q12: 启动时报 "Could not load the sharp module" 或 "ld-linux-x86-64.so.2" 错误？

**答：** 这是因为 Docker 镜像如果使用了 Alpine 基础镜像（Alpine Linux 使用 musl 库），DSH 的 `sharp` 和 `koffi` 原生模块需要 glibc（GNU C 库）才能加载。

**当前版本已修复：** 最新版镜像已使用 `debian:bookworm-slim`（Debian glibc）作为基础镜像，不再有这个问题。

**如果旧镜像已部署到内网，需要替换：**

```bash
# 1. 备份数据
cp -r dsh-home dsh-home.bak
cp -r workspace workspace.bak

# 2. 停止并删除旧容器
docker stop dsh && docker rm dsh

# 3. 删除旧镜像
docker rmi localhost/dsh-offline:latest 2>/dev/null
docker rmi dsh-offline:latest

# 4. 加载新镜像
docker load -i dsh-offline-image.tar.gz

# 5. 重新部署
./deploy.sh
```

---

## 13. 文件清单

### 本项目目录（`01-dsh-config-files/`）

| 文件 | 用途 |
|------|------|
| `dsh-offline-image.tar.gz` | DSH 完整 Docker 镜像（x86_64，Debian glibc，约 500MB） |
| `pnpm-linux-x64` | pnpm 包管理器离线包（约 64MB，用于本地构建） |
| `Dockerfile` | 本地构建 DSH 镜像（基于 debian:bookworm-slim） |
| `Dockerfile.ci` | GitHub Actions CI 构建专用 Dockerfile |
| `.github/workflows/build-dsh-image.yml` | GitHub Actions 自动构建工作流 |
| `docker-compose.yml` | 容器编排（端口 3080、数据持久化） |
| `settings.yaml` | **双环境配置**：测试环境（3个模型）+ 生产环境（5个模型） |
| `docker-entrypoint.sh` | 容器入口脚本（内置 Node.js TCP 转发） |
| `.dockerignore` | 构建优化 |
| `build-and-save.sh` | 本地有网环境：构建 + 导出 USB 交付包 |
| `build-dsh-image.sh` | 本地有网环境：仅构建 Docker 镜像 |
| `deploy.sh` | 内网环境：一键加载 + 启动容器（支持双环境模式） |
| `prepare-docker-offline.sh` | 有网环境：准备 Docker 离线安装包（支持 RHEL/CentOS/Ubuntu） |
| `pack-and-send.sh` | 有网环境：打包分卷脚本（用于邮箱发送） |
| `README.md` | 本指南 |
| `node-v22.19.0-linux-x64.tar.xz` | Node.js 22 运行时（备用） |
| `deepseek-ai-dsh-0.1.0-rc.7.tgz` | DSH 源码包（备用） |

### 部署包目录结构（`dsh-deploy/`）

| 文件/目录 | 大小 | 说明 |
|-----------|------|------|
| `01-dsh-config-files/` | - | 上述所有配置和脚本文件 |
| `dsh-offline-image.tar.gz` | ~422MB | DSH Docker 镜像（Debian glibc） |
| `pnpm-linux-x64` | ~64MB | pnpm 包管理器（移入配置目录后使用） |

---

## 最终检查清单

### 测试环境
- [ ] ✅ 有网电脑上已执行 `./build-and-save.sh` 构建成功
- [ ] ✅ `dsh-usb-bundle/` 已复制到 U 盘
- [ ] ✅ 测试环境 Ubuntu 服务器已安装 Docker
- [ ] ✅ USB 交付包已复制到测试环境服务器（`df -h` 确认空间足够）
- [ ] ✅ `./deploy.sh` 执行成功（选择选项 1 测试环境），容器正常运行
- [ ] ✅ ufw 已开放 3080 端口
- [ ] ✅ 浏览器可访问 Web UI
- [ ] ✅ 算力服务器 vLLM Ascend 服务正常运行
- [ ] ✅ 测试环境服务器可访问算力服务器（`curl <IP>:8000/v1/models`）
- [ ] ✅ `settings.yaml` 已替换测试环境算力服务器实际 IP
- [ ] ✅ Web UI 中已确认模型配置正确
- [ ] ✅ 已选择默认模型 `DeepSeek-R1-Distill-Llama-70B`
- [ ] ✅ 已创建工作区，可正常发送任务并得到回复
- [ ] ✅ 测试了图片上传和多模态问答，功能正常

### 生产环境
- [ ] ✅ 测试环境验证全部通过
- [ ] ✅ `dsh-usb-bundle/` 已复制到生产环境服务器
- [ ] ✅ `./deploy.sh` 执行成功（选择选项 2 生产环境），容器正常运行
- [ ] ✅ firewalld 已开放 3080 端口
- [ ] ✅ 浏览器可访问 Web UI
- [ ] ✅ 生产环境服务器可访问生产算力服务器
- [ ] ✅ `settings.yaml` 已替换生产环境算力服务器实际 IP
- [ ] ✅ 默认模型已改为 `DeepSeek-V4-Flash-w8a8-mtp`
- [ ] ✅ Web UI 中已确认模型配置正确
- [ ] ✅ 已选择默认模型
- [ ] ✅ 已创建工作区，可正常发送任务
- [ ] ✅ 部署完成，投产