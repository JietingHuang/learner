# DeepSeek Harness (DSH) 内网部署指南

> 版本：0.1.0-rc.7 | 协议：MIT
> 适用环境：完全物理隔离内网 | **先测试后生产部署** | 虚拟化服务器(Ubuntu 20.04.6 LTS 测试环境 → RHEL 8.9 生产环境) | 算力服务器(鲲鹏920+昇腾910B) 运行 vLLM Ascend

---

## 目录

1. [你的架构概况](#1-你的架构概况)
2. [获取部署包](#2-获取部署包)
3. [前提条件](#3-前提条件)
4. [测试环境部署 (Ubuntu 20.04)](#4-测试环境部署-ubuntu-2004)
5. [配置模型](#5-配置模型)
6. [验证与日常运维](#6-验证与日常运维)
7. [生产环境部署 (RHEL 8.9)](#7-生产环境部署-rhel-89)
8. [离线安装 Docker](#8-离线安装-docker)
9. [常见问题](#9-常见问题)
10. [文件清单](#10-文件清单)

---

## 1. 你的架构概况

| 环境 | 服务器 | 操作系统 | 角色 |
|------|--------|----------|------|
| **测试环境** | 虚拟化服务器 (x86) | Ubuntu 20.04.6 LTS | 运行 DSH Web UI + Agent 引擎 |
| **生产环境** | 虚拟化服务器 (x86) | RHEL 8.9 | 运行 DSH Web UI + Agent 引擎 |
| **算力服务器** | 华鲲 AT3500 G3-792 | 鲲鹏920(ARM) + 昇腾910B × 16卡 | 运行 vLLM Ascend 模型推理 |

### 测试环境已部署模型（vLLM Ascend）

| 模型 | 用途 |
|------|------|
| **DeepSeek-R1-Distill-Llama-70B** | Agent 主模型 — 推理、思考、规划 |
| **Qwen3-32B** | 通用对话模型 |
| **Qwen3-VL-30B-A3B-Instruct** | 多模态 — 图片理解 |

### 生产环境已部署模型（vLLM Ascend）

| 模型 | 用途 |
|------|------|
| **DeepSeek-V4-Flash-w8a8-mtp** | Agent 主模型 — 代码生成、推理、对话 |
| **Qwen3-VL-30B-A3B-Instruct** | 多模态 — 图片理解 |
| **PaddleOCR-VL-0.9B** | OCR 文字识别 |
| **Qwen3-VL-Embedding-8B** | 向量嵌入 — 语义检索 |
| **Qwen3-VL-Reranker-8B** | 重排序 — 搜索结果精排 |

**算力已经有了，你只需要搭建 DSH Web UI 即可。**

---

## 2. 获取部署包

镜像已通过 GitHub Actions 自动构建完成，发布在 GitHub Release 中。

### 2.1 下载 Release

打开以下链接，下载两个文件：

> https://github.com/JietingHuang/learner/releases/latest

| 文件 | 大小 | 用途 |
|------|------|------|
| `dsh-offline-image.tar.gz` | ~400MB | Docker 镜像（内含 Node.js 22 + pnpm + DSH + 所有系统依赖） |
| `dsh-deploy-pack.zip` | ~35KB | 完整部署脚本和配置文件 |

### 2.2 传输到内网服务器

通过 U 盘将两个文件复制到内网虚拟化服务器：

```bash
# 插入 U 盘后，查看设备
lsblk
# 找到 U 盘设备，如 /dev/sdb1

# 挂载 U 盘
sudo mkdir -p /mnt/usb
sudo mount /dev/sdb1 /mnt/usb

# 复制文件到本地（找一个空间 > 1GB 的目录）
cp /mnt/usb/dsh-offline-image.tar.gz .
cp /mnt/usb/dsh-deploy-pack.zip .

# 卸载 U 盘
sync
sudo umount /mnt/usb
```

### 2.3 解压部署脚本

```bash
unzip dsh-deploy-pack.zip
cd scripts
ls -la
# 应该看到 deploy.sh、settings.yaml、docker-compose.yml 等文件
```

---

## 3. 前提条件

### 3.1 确认网络连通性

在 **测试环境虚拟化服务器** 上执行，确认能访问算力服务器的 vLLM API：

```bash
# 替换为你的算力服务器实际 IP
curl -s http://<算力服务器IP>:8000/v1/models
```

**预期结果：** 返回 JSON 格式的模型列表。

### 3.2 检查磁盘空间

```bash
df -h
# 找一个可用空间大于 1GB 的分区
```

---

## 4. 测试环境部署 (Ubuntu 20.04)

### 4.1 检查 Docker

```bash
docker --version
# 如果没装，先跳到第 8 章【离线安装 Docker】
```

### 4.2 加载 Docker 镜像

```bash
# 从 Release 下载的 dsh-offline-image.tar.gz 文件所在目录执行
docker load -i dsh-offline-image.tar.gz

# 验证加载成功
docker images | grep dsh
# 应看到 dsh-offline:latest
```

### 4.3 一键部署

```bash
# 进入 scripts 目录
cd scripts

# 赋予执行权限
chmod +x deploy.sh

# 执行部署
./deploy.sh
```

### 4.4 部署脚本执行流程

**第 1 步：** 检测操作系统信息。

**第 2 步：** 选择部署环境：
```
请选择部署环境：
  1) 测试环境（Ubuntu 20.04）— 推荐
  2) 生产环境（RHEL 8.9）
请输入选项 (1/2):
```
输入 **1** 后回车。

**第 3 步：** 检测 Docker 是否正常运行。

**第 4 步：** 自动检测镜像文件格式（gzip / xz / tar / bzip2）并加载。

**第 5 步：** 创建 `workspace/` 和 `dsh-home/` 目录，复制 `settings.yaml` 配置模板。

**第 6 步：** ⚠️ **脚本暂停，提示你编辑配置文件**：
```
⚠️  重要：请编辑 dsh-home/settings.yaml
   将 <测试环境算力服务器IP> 替换为实际内网 IP
```
此时打开另一个终端窗口，编辑配置：
```bash
vim dsh-home/settings.yaml
```
找到所有 `baseURL` 行，把 `<测试环境算力服务器IP>` 替换为实际 IP（如 `192.168.1.100`），保存退出。
> 需要替换的地方有 3 处（DeepSeek、Qwen3、Qwen3-VL 三个模型）。

**第 7 步：** 脚本自动启动容器（`--network host` 模式），容器内部：
- DSH 绑定 `127.0.0.1:3080`（DSH 安全策略限制）
- Node.js TCP 转发 `0.0.0.0:3080 → 127.0.0.1:3080`

**第 8 步：** 看到以下输出说明部署成功：
```
✅ 启动成功！
   访问地址: http://<服务器IP>:3080
```

### 4.5 开放防火墙

```bash
# Ubuntu
sudo ufw allow 3080/tcp
sudo ufw status
```

---

## 5. 配置模型

### 5.1 确认 settings.yaml

编辑 `dsh-home/settings.yaml`，确保：
1. 所有 `baseURL` 中的 IP 已替换为算力服务器的实际内网 IP
2. 默认模型使用 `test-ascend-deepseek` / `DeepSeek-R1-Distill-Llama-70B`

修改后重启容器：
```bash
docker restart dsh
```

### 5.2 通过 Web UI 配置（备选）

1. 浏览器访问 `http://<服务器IP>:3080`
2. 点击 **设置 → 模型**
3. 添加三个提供方（OpenAI 兼容协议）：

| Provider ID | 模型 | 基础 URL |
|-------------|------|----------|
| `test-ascend-deepseek` | `DeepSeek-R1-Distill-Llama-70B` | `http://<算力IP>:8000/v1` |
| `test-ascend-qwen` | `Qwen3-32B` | `http://<算力IP>:8000/v1` |
| `test-ascend-qwen-vl` | `Qwen3-VL-30B-A3B-Instruct` | `http://<算力IP>:8000/v1` |

---

## 6. 验证与日常运维

### 6.1 验证容器状态

```bash
docker ps -a | grep dsh
# STATUS 应为 Up
```

### 6.2 查看启动日志

```bash
docker logs dsh --tail 50
# 应看到: ✅ 端口转发已就绪，等待连接...
```

### 6.3 首次访问 Web UI

浏览器访问 `http://<服务器IP>:3080`，看到 DSH 界面即部署成功。

### 6.4 测试对话

1. 点击 **+ 新建工作区**
2. 输入 `你好，请介绍一下你自己`
3. 发送，等待回复

### 6.5 日常运维命令

```bash
# 查看容器状态
docker ps -a | grep dsh

# 查看实时日志
docker logs -f dsh

# 重启容器
docker restart dsh

# 停止容器
docker stop dsh

# 启动容器
docker start dsh

# 进入容器内部
docker exec -it dsh bash

# 删除容器并重新部署
docker stop dsh && docker rm dsh
./deploy.sh
```

---

## 7. 生产环境部署 (RHEL 8.9)

### 7.1 复制文件到生产服务器

测试环境验证通过后，将同样的 `dsh-offline-image.tar.gz` 和 `dsh-deploy-pack.zip` 复制到生产环境服务器。

### 7.2 部署

```bash
docker load -i dsh-offline-image.tar.gz
unzip dsh-deploy-pack.zip && cd scripts
chmod +x deploy.sh
./deploy.sh
# 选择选项 2 (生产环境)
```

### 7.3 编辑配置

编辑 `dsh-home/settings.yaml`：
1. 替换 `<生产环境算力服务器IP>` 为实际 IP
2. 默认模型改为：
   ```yaml
   agent-default-model:
     provider: prod-ascend-deepseek
     model: DeepSeek-V4-Flash-w8a8-mtp
   ```

### 7.4 开放防火墙

```bash
sudo firewall-cmd --add-port=3080/tcp --permanent
sudo firewall-cmd --reload
sudo firewall-cmd --list-ports
```

---

## 8. 离线安装 Docker

### 测试环境（Ubuntu 20.04）

在 **有网电脑** 上执行：
```bash
./prepare-docker-offline.sh
# 选择选项 3 → Ubuntu → 20.04 (focal)
# 将生成的 docker-offline-pkg/ 复制到 U 盘
```

在 **内网服务器** 上执行：
```bash
sudo mount /dev/sdb1 /mnt/usb
cp -r /mnt/usb/docker-offline-pkg ~/
cd ~/docker-offline-pkg
sudo dpkg -i *.deb
sudo systemctl start docker
sudo systemctl enable docker
docker --version
```

### 生产环境（RHEL 8.9）

在 **有网电脑** 上执行：
```bash
./prepare-docker-offline.sh
# 选择选项 1 → RHEL 8.9 / CentOS 8
```

在 **内网服务器** 上执行：
```bash
sudo mount /dev/sdb1 /mnt/usb
cp -r /mnt/usb/docker-offline-pkg ~/
cd ~/docker-offline-pkg
sudo rpm -ivh *.rpm
sudo systemctl start docker
sudo systemctl enable docker
docker --version
```

---

## 9. 常见问题

#### ❌ telnet 3080 不通，容器状态正常

```bash
# 检查容器日志
docker logs dsh | grep "端口转发"
# 应看到: ✅ 端口转发已就绪

# 检查端口监听
sudo ss -tlnp | grep 3080

# 检查防火墙
sudo ufw status | grep 3080
```

#### ❌ 容器反复重启

```bash
docker logs dsh --tail 20
```
如果看到 `--host 0.0.0.0 is intentionally not supported`，说明这是 DSH 安全策略限制，`docker-entrypoint.sh` 已内置 Node.js 转发解决此问题，确保使用最新版镜像。

#### ❌ 加载镜像报 "no space left on device"

```bash
df -h
# 找空间大的分区，重新操作
```

#### ❌ YAML 解析错误

```bash
# 确保 baseURL 的值用双引号包裹
baseURL: "http://192.168.1.100:8000/v1"
```

---

## 10. 文件清单

### dsh-deploy-pack.zip 内容

| 文件 | 用途 |
|------|------|
| `scripts/deploy.sh` | 一键部署脚本（加载镜像 + 启动容器） |
| `scripts/Dockerfile` | 本地构建 Dockerfile（debian:bookworm-slim） |
| `scripts/Dockerfile.ci` | GitHub Actions 构建专用 Dockerfile |
| `scripts/docker-compose.yml` | 容器编排配置 |
| `scripts/docker-entrypoint.sh` | 容器入口（内置 Node.js TCP 端口转发） |
| `scripts/settings.yaml` | 双环境模型配置模板 |
| `scripts/prepare-docker-offline.sh` | Docker 离线安装包准备脚本 |
| `scripts/build-dsh-image.sh` | 本地构建 Docker 镜像（有网电脑用） |
| `scripts/pack-and-send.sh` | 打包分卷脚本 |
| `scripts/README.md` | 本指南 |
| `scripts/.dockerignore` | 构建优化配置 |
| `intranet-tools/` | 内网工具栈（Portainer、Gitea、Grafana 等） |
| `.github/workflows/build-dsh-image.yml` | GitHub Actions 自动构建工作流 |

### 关键文件说明

| 文件 | 大小 | 说明 |
|------|------|------|
| `dsh-offline-image.tar.gz` | ~400MB | Docker 镜像，内含 Node.js 22 + pnpm + DSH + 系统依赖 |
| `dsh-deploy-pack.zip` | ~35KB | 上述所有部署脚本和配置文件 |

> **你只需要这两个文件。** pnpm、Node.js 和 DSH 都已内置在 Docker 镜像中，无需单独下载。