#!/bin/bash
set -e

# ============================================================================
# DSH Docker 镜像构建脚本
# 在【有网络的电脑】上运行，构建基于 Debian glibc 的 Docker 镜像
# 解决 Alpine 镜像中 sharp/koffi 等原生模块加载失败的问题
# ============================================================================
# 使用方式：
#   chmod +x build-dsh-image.sh
#   sudo bash build-dsh-image.sh
#
# 前提条件：
#   - 已安装 Docker（docker --version 确认）
#   - 网络畅通（能访问 Docker Hub）
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

IMAGE_NAME="dsh-offline"
IMAGE_TAG="latest"
IMAGE_FILE="dsh-offline-image.tar.gz"

echo "=========================================="
echo "  DSH Docker 镜像构建脚本"
echo "  基于 Debian bookworm（glibc）"
echo "  架构: linux/amd64"
echo "=========================================="
echo ""

# 检查 Docker
if ! command -v docker &> /dev/null; then
    echo "❌ 错误: 未找到 Docker。请先安装 Docker。"
    echo "   安装参考: https://docs.docker.com/engine/install/"
    exit 1
fi

# 检查必需文件（本地文件）
REQUIRED_FILES=(
    "node-v22.19.0-linux-x64.tar.xz"
    "pnpm-linux-x64"
    "deepseek-ai-dsh-0.1.0-rc.7.tgz"
    "settings.yaml"
    "docker-entrypoint.sh"
)

# 检查文件是否存在
for f in "node-v22.19.0-linux-x64.tar.xz" "pnpm-linux-x64" "deepseek-ai-dsh-0.1.0-rc.7.tgz" "settings.yaml" "docker-entrypoint.sh"; do
    if [ ! -f "$f" ]; then
        echo "❌ 错误: 缺少必需文件: $f"
        echo "   请确保所有文件与脚本在同一目录下"
        exit 1
    fi
done

echo "✅ 所有必需文件已就绪"
echo ""

# 步骤 1: 拉取基础镜像
echo "=========================================="
echo "  📥 步骤 1/4: 拉取基础镜像"
echo "=========================================="
echo ""
echo "  镜像: debian:bookworm-slim"
echo ""

docker pull debian:bookworm-slim

echo "✅ 基础镜像拉取完成"
echo ""

# 步骤 2: 构建 DSH 镜像
echo "=========================================="
echo "  🏗️  步骤 2/4: 构建 DSH 镜像"
echo "=========================================="
echo ""

echo "  Dockerfile 已使用 debian:bookworm-slim 作为基础镜像"
echo "  构建命令: docker build -t ${IMAGE_NAME}:${IMAGE_TAG} ."
echo ""

docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" .

echo "✅ DSH 镜像构建完成"
echo ""

# 步骤 3: 导出镜像
echo "=========================================="
echo "  📦 步骤 3/4: 导出镜像为 tar.gz"
echo "=========================================="
echo ""

echo "  导出镜像: ${IMAGE_NAME}:${IMAGE_TAG} -> ${IMAGE_FILE}"
echo ""

docker save "${IMAGE_NAME}:${IMAGE_TAG}" | gzip > "${IMAGE_FILE}"

echo "✅ 镜像导出完成"
echo "  文件大小: $(du -h "${IMAGE_FILE}" | cut -f1)"
echo ""

# 步骤 4: 验证
echo "=========================================="
echo "  ✅ 步骤 4/4: 验证镜像"
echo "=========================================="
echo ""

echo "  镜像信息:"
docker images "${IMAGE_NAME}:${IMAGE_TAG}" --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}"
echo ""

echo "  验证镜像内容:"
echo "    - 基础系统: Debian bookworm (glibc)"
echo "    - Node.js: $(docker run --rm ${IMAGE_NAME}:${IMAGE_TAG} node --version 2>/dev/null || echo '验证失败，请检查')"
echo "    - 入口脚本: /usr/local/bin/docker-entrypoint.sh"
echo ""

echo "=========================================="
echo "  🎉 构建完成！"
echo "=========================================="
echo ""
echo "  镜像文件: ${IMAGE_FILE}"
echo "  大小: $(du -h "${IMAGE_FILE}" | cut -f1)"
echo ""
echo "  将 ${IMAGE_FILE} 复制到内网服务器，然后执行："
echo "    docker load -i ${IMAGE_FILE}"
echo "    bash deploy.sh"
echo ""
echo "  如需删除旧镜像，请执行："
echo "    docker stop dsh 2>/dev/null; docker rm dsh 2>/dev/null"
echo "    docker images | grep dsh-offline  # 查看所有 DSH 镜像"
echo "    docker rmi dsh-offline:latest      # 删除旧镜像"
echo "    docker rmi localhost/dsh-offline:latest  # 删除带 localhost 前缀的镜像"
echo "    docker load -i ${IMAGE_FILE}       # 加载新镜像"
echo "    bash deploy.sh                     # 重新部署"
echo ""

# 清理旧镜像标签（可选）
echo "是否需要清理旧版本的 DSH 镜像？(y/N): "
read -r CLEAN_OLD
if [ "$CLEAN_OLD" = "y" ] || [ "$CLEAN_OLD" = "Y" ]; then
    echo "正在清理旧镜像..."
    docker images | grep dsh-offline | grep -v "${IMAGE_TAG}" | awk '{print $1":"$2}' | xargs -r docker rmi 2>/dev/null || true
    echo "✅ 旧镜像已清理"
fi

echo ""
echo "=========================================="
echo "  📋 后续操作说明"
echo "=========================================="
echo ""
echo "  1. 将 ${IMAGE_FILE} 复制到 U 盘"
echo "  2. 带到内网虚拟化服务器"
echo "  3. 加载镜像: docker load -i ${IMAGE_FILE}"
echo "  4. 部署: bash deploy.sh"
echo "  5. 访问: http://服务器IP:3080"
echo ""