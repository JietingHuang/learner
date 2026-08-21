#!/bin/bash
set -e

# ============================================================================
# DSH 部署包打包分卷脚本
# 在【有网络的电脑】上运行，构建 Docker 镜像并打包为分卷 ZIP
# ============================================================================
# 使用方式：
#   chmod +x pack-and-send.sh
#   sudo bash pack-and-send.sh
#
# 前提条件：
#   - 已安装 Docker（docker --version 确认）
#   - 已安装 zip（zip --version 确认）
#   - 网络畅通（能访问 Docker Hub）
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# =============================================
# 步骤 1: 构建 Docker 镜像
# =============================================
echo "=========================================="
echo "  📥 步骤 1/4: 构建 DSH Docker 镜像"
echo "=========================================="
echo ""
echo "  正在构建镜像（基于 debian:bookworm-slim）..."
echo ""

docker build -t dsh-offline:latest .

echo "✅ 镜像构建完成"
echo ""

# 导出镜像
echo "  导出镜像中..."
docker save dsh-offline:latest | gzip > dsh-offline-image.tar.gz
echo "✅ 镜像已导出: dsh-offline-image.tar.gz ($(du -h dsh-offline-image.tar.gz | cut -f1))"
echo ""

# =============================================
# 步骤 2: 准备分卷
# =============================================
echo "=========================================="
echo "  📦 步骤 2/4: 分卷打包"
echo "=========================================="
echo ""

# 清理旧分卷
rm -f dsh-deploy.z01 dsh-deploy.z02 dsh-deploy.zip 2>/dev/null

# 计算镜像文件大小，决定分卷数量
IMAGE_SIZE=$(stat -c%s dsh-offline-image.tar.gz 2>/dev/null || stat -f%z dsh-offline-image.tar.gz 2>/dev/null)
echo "  镜像文件大小: $(numfmt --to=iec $IMAGE_SIZE 2>/dev/null || echo $IMAGE_SIZE)"

# 使用 zip 分卷（每卷 45MB，适配 QQ 邮箱附件限制）
echo "  创建分卷（每卷 45MB）..."
echo ""

# 先创建分卷目录
mkdir -p dsh-split

# 将镜像和配置文件分卷打包
# 总文件列表：
#   dsh-offline-image.tar.gz  ~422MB
#   pnpm-linux-x64           ~64MB
#   node-v22.19.0-linux-x64.tar.xz ~30MB
#   deepseek-ai-dsh-0.1.0-rc.7.tgz ~33KB
#   Dockerfile, build*.sh, deploy.sh, settings.yaml, docker-entrypoint.sh, README.md  ~1MB

echo "=========================================="
echo "  📦 分卷文件清单"
echo "=========================================="
echo ""
echo "  分卷 1: 配置文件包 (01-dsh-config-files.zip)"
echo "    - Dockerfile, *.sh, settings.yaml, docker-entrypoint.sh"
echo "    - README.md, docker-compose.yml, .dockerignore"
echo "    - node-v22.19.0-linux-x64.tar.xz"
echo "    - deepseek-ai-dsh-0.1.0-rc.7.tgz"
echo ""
echo "  分卷 2-10: Docker 镜像包 (dsh-image-part-00 ~ 08)"
echo "    - dsh-offline-image.tar.gz 分卷（每卷 45MB）"
echo ""
echo "  分卷 11-12: pnpm 包 (pnpm-part-00 ~ 01)"
echo "    - pnpm-linux-x64 分卷（每卷 45MB）"
echo ""
echo "=========================================="
echo ""

# =============================================
# 步骤 3: 创建配置文件包
# =============================================
echo "🔍 步骤 3/4: 创建配置文件包..."

# 创建临时目录
TMP_CONFIG_DIR=$(mktemp -d)
cp Dockerfile "$TMP_CONFIG_DIR/"
cp build-and-save.sh "$TMP_CONFIG_DIR/"
cp build-dsh-image.sh "$TMP_CONFIG_DIR/"
cp deploy.sh "$TMP_CONFIG_DIR/"
cp settings.yaml "$TMP_CONFIG_DIR/"
cp docker-entrypoint.sh "$TMP_CONFIG_DIR/"
cp .dockerignore "$TMP_CONFIG_DIR/" 2>/dev/null || true
cp docker-compose.yml "$TMP_CONFIG_DIR/"
cp README.md "$TMP_CONFIG_DIR/"
cp prepare-docker-offline.sh "$TMP_CONFIG_DIR/"
cp node-v22.19.0-linux-x64.tar.xz "$TMP_CONFIG_DIR/"
cp deepseek-ai-dsh-0.1.0-rc.7.tgz "$TMP_CONFIG_DIR/"
cp pack-and-send.sh "$TMP_CONFIG_DIR/"

# 打包配置文件
cd "$TMP_CONFIG_DIR"
zip -9 "$SCRIPT_DIR/01-dsh-config-files.zip" ./*
cd "$SCRIPT_DIR"
rm -rf "$TMP_CONFIG_DIR"

echo "✅ 配置文件包已创建: 01-dsh-config-files.zip ($(du -h 01-dsh-config-files.zip | cut -f1))"
echo ""

# =============================================
# 步骤 4: 创建镜像分卷
# =============================================
echo "🔍 步骤 4/4: 创建镜像分卷..."

# 镜像分卷
split -b 45M -d -a 2 dsh-offline-image.tar.gz dsh-image-part-
# 重命名为可读的文件名
for f in dsh-image-part-*; do
    num=${f##dsh-image-part-}
    mv "$f" "dsh-image-part-${num}"
done
echo "✅ 镜像分卷已创建（共 $(ls dsh-image-part-* 2>/dev/null | wc -l) 个文件）"

# pnpm 分卷
split -b 45M -d -a 2 pnpm-linux-x64 pnpm-part-
for f in pnpm-part-*; do
    num=${f##pnpm-part-}
    mv "$f" "pnpm-part-${num}"
done
echo "✅ pnpm 分卷已创建（共 $(ls pnpm-part-* 2>/dev/null | wc -l) 个文件）"

echo ""
echo "=========================================="
echo "  🎉 打包完成！"
echo "=========================================="
echo ""
echo "  生成的文件："
echo "  📄 01-dsh-config-files.zip    ($(du -h 01-dsh-config-files.zip | cut -f1))"
echo "  📦 dsh-image-part-* × $(ls dsh-image-part-* 2>/dev/null | wc -l) 个"
echo "  📦 pnpm-part-* × $(ls pnpm-part-* 2>/dev/null | wc -l) 个"
echo ""
echo "  总大小：$(du -sh 01-dsh-config-files.zip dsh-image-part-* pnpm-part-* 2>/dev/null | tail -1 | cut -f1)"
echo ""
echo "  发送方式："
echo "  1. 登录 QQ 邮箱: https://mail.qq.com"
echo "  2. 点击"写信""
echo "  3. 收件人: imjieting@qq.com"
echo "  4. 主题: DSH 部署包"
echo "  5. 点击"超大附件"（每封邮件最多 2GB）"
echo "  6. 将 01-dsh-config-files.zip 作为第1封邮件附件发送"
echo "  7. 将 dsh-image-part-00 ~ 08 作为第2封邮件附件发送"
echo "  8. 将 pnpm-part-00 ~ 01 作为第3封邮件附件发送"
echo ""
echo "  收到后合并："
echo "    cat dsh-image-part-* > dsh-offline-image.tar.gz"
echo "    cat pnpm-part-* > pnpm-linux-x64"
echo "    unzip 01-dsh-config-files.zip -d dsh-deploy"
echo ""

# 清理临时镜像文件
rm -f dsh-offline-image.tar.gz