#!/bin/bash
set -e

# ============================================================================
# DSH 离线部署包构建脚本
# 在【有网络的电脑】上运行，构建 Docker 镜像并导出为 tar 包
# 构建完成后，将整个 USB_DIR 目录拷贝到 U 盘，带到内网服务器部署
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

IMAGE_NAME="dsh-offline"
IMAGE_TAG="latest"
IMAGE_FILE="dsh-offline-image.tar.gz"
BASE_IMAGE_FILE="debian-bookworm-slim.tar.gz"
USB_DIR="dsh-usb-bundle"

echo "=========================================="
echo "  DeepSeek Harness 离线部署包构建脚本"
echo "  适用于 完全物理隔离（USB 交付）环境"
echo "=========================================="
echo ""

# 检查 Docker
if ! command -v docker &> /dev/null; then
    echo "❌ 错误: 未找到 Docker。请先安装 Docker。"
    echo "   安装参考: https://docs.docker.com/engine/install/"
    exit 1
fi

echo "=========================================="
echo "  🏗️  阶段一：构建 DSH 镜像"
echo "=========================================="
echo ""

# 步骤 1: 拉取 Debian 基础镜像
echo "🔍 步骤 1/5: 拉取 Debian 基础镜像..."
echo "    镜像: debian:bookworm-slim"
echo ""

docker pull debian:bookworm-slim

echo "✅ 步骤 1/5 完成"
echo ""

# 步骤 2: 构建 DSH 镜像
echo "🔍 步骤 2/5: 构建 DSH 镜像..."
echo "    镜像名: ${IMAGE_NAME}:${IMAGE_TAG}"
echo ""

docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" .

echo "✅ 步骤 2/5 完成"
echo ""

echo "=========================================="
echo "  📦 阶段二：导出镜像为 tar 包"
echo "=========================================="
echo ""

# 步骤 3: 导出 DSH 镜像
echo "🔍 步骤 3/5: 导出 DSH 镜像..."
echo "    输出文件: ${IMAGE_FILE}"
echo ""

docker save "${IMAGE_NAME}:${IMAGE_TAG}" | gzip > "${IMAGE_FILE}"
echo "✅ 步骤 3/5 完成"
echo "    文件大小: $(du -h "${IMAGE_FILE}" | cut -f1)"
echo ""

# 步骤 4: 导出 Debian 基础镜像（备用）
echo "🔍 步骤 4/5: 导出 Debian 基础镜像（备用）..."
echo "    输出文件: ${BASE_IMAGE_FILE}"
echo ""

docker save debian:bookworm-slim | gzip > "${BASE_IMAGE_FILE}"
echo "✅ 步骤 4/5 完成"
echo "    文件大小: $(du -h "${BASE_IMAGE_FILE}" | cut -f1)"
echo ""

echo "=========================================="
echo "  📀 阶段三：组装 USB 交付包"
echo "=========================================="
echo ""

# 步骤 5: 组装 USB 交付包
echo "🔍 步骤 5/5: 组装 USB 交付包..."
echo "    目标目录: ${USB_DIR}/"
echo ""

# 清理旧目录
rm -rf "$USB_DIR"
mkdir -p "$USB_DIR"

# 复制所有部署所需的文件
cp "${IMAGE_FILE}"         "$USB_DIR/"   # DSH 镜像
cp "${BASE_IMAGE_FILE}"    "$USB_DIR/"   # Debian 基础镜像（备用）
cp docker-compose.yml      "$USB_DIR/"   # 容器编排配置
cp settings.yaml           "$USB_DIR/"   # 模型配置模板
cp deploy.sh               "$USB_DIR/"   # 内网部署脚本
cp docker-entrypoint.sh    "$USB_DIR/"   # 容器入口脚本（必须）
cp .dockerignore           "$USB_DIR/" 2>/dev/null || true  # Docker 构建忽略文件
cp Dockerfile              "$USB_DIR/"   # Dockerfile（备用，可在内网重建镜像）
cp README.md               "$USB_DIR/"   # 部署指南

# 赋予执行权限
chmod +x "$USB_DIR/deploy.sh"
chmod +x "$USB_DIR/docker-entrypoint.sh"

# 计算总大小
echo "✅ 步骤 5/5 完成"
echo ""

echo "=========================================="
echo "  🎉 构建完成！USB 交付包已就绪"
echo "=========================================="
echo ""
echo "USB 目录位置: ${USB_DIR}/"
echo "总大小: $(du -sh "${USB_DIR}" | cut -f1)"
echo ""
echo "USB 目录内容:"
echo "  📦 ${IMAGE_FILE}            — DSH Docker 镜像（核心文件）"
echo "  📦 ${BASE_IMAGE_FILE}       — Debian 基础镜像（备用）"
echo "  📄 docker-compose.yml       — 容器编排配置"
echo "  📄 settings.yaml            — 模型配置模板"
echo "  📄 deploy.sh                — 内网部署脚本（已赋执行权限）"
echo "  📄 docker-entrypoint.sh     — 容器入口脚本（已赋执行权限）"
echo "  📄 Dockerfile               — Dockerfile（备用）"
echo "  📄 README.md                — 部署指南"
echo ""
echo "=========================================="
echo "  📋 接下来的操作（USB 交付流程）"
echo "=========================================="
echo ""
echo "  第 1 步：将 ${USB_DIR}/ 目录整个复制到 U 盘"
echo "     $ cp -r ${USB_DIR} /Volumes/U盘/"
echo ""
echo "  第 2 步：把 U 盘插入内网服务器"
echo ""
echo "  第 3 步：在内网服务器上执行部署"
echo "     $ cd /path/to/${USB_DIR}"
echo "     $ bash deploy.sh"
echo ""
echo "  第 4 步：访问 Web UI"
echo "     浏览器打开 http://服务器IP:3080"
echo ""
echo "=========================================="
echo "  ⚠️  重要提示"
echo "=========================================="
echo ""
echo "  1. 如果内网服务器没有安装 Docker，请先参考 README.md"
echo "     中的『附录：Docker 离线安装』章节，安装 Docker。"
echo ""
echo "  2. 内网还需要有模型推理服务（如 vLLM / Ollama 等），"
echo "     否则 DSH 无法正常工作。模型镜像也需要单独搬运。"
echo ""

# 清理临时镜像文件（保留 USB 目录中的完整副本）
rm -f "${IMAGE_FILE}" "${BASE_IMAGE_FILE}"