#!/bin/bash
set -e

# ============================================================================
# DSH 内网部署脚本 — 适配 Ubuntu 20.04 / RHEL 8.9 + 昇腾算力分离架构
# 在内网虚拟化服务器上运行，加载 Docker 镜像并启动容器
# ============================================================================
# 架构说明：
#   虚拟化服务器（Ubuntu 20.04 测试环境 / RHEL 8.9 生产环境）→ 运行 DSH 容器
#   算力服务器（华鲲 AT3500 G3-792）→ 运行 vLLM Ascend（已就绪）
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# 支持多种文件名和格式
# 优先查找顺序：dsh-offline-image.tar.gz → dsh-offline.tar.gz → dsh-offline-image.tar → dsh-offline.tar
# 格式不限，后续会自动检测
IMAGE_TAR=""
for f in dsh-offline-image.tar.gz dsh-offline.tar.gz dsh-offline-image.tar dsh-offline.tar; do
    if [ -f "$f" ]; then
        IMAGE_TAR="$f"
        break
    fi
done

if [ -z "$IMAGE_TAR" ]; then
    echo "❌ 错误: 未找到镜像文件"
    echo "   支持的格式: dsh-offline-image.tar.gz / dsh-offline.tar.gz / dsh-offline-image.tar / dsh-offline.tar"
    echo "   当前目录内容："
    ls -la 2>/dev/null
    exit 1
fi
IMAGE_NAME="dsh-offline"
IMAGE_TAG="latest"
# 实际加载的镜像名（可能带 localhost/ 前缀，由 docker load 输出决定）
LOADED_IMAGE=""

echo "=========================================="
echo "  DeepSeek Harness 内网部署脚本"
echo "  架构：虚拟化服务器 + 昇腾算力机"
echo "=========================================="
echo ""

# ---- 检测操作系统 ----
OS=""
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    OS_VERSION=$VERSION_ID
elif grep -qi "ubuntu" /etc/*release 2>/dev/null; then
    OS="ubuntu"
elif grep -qi "rhel\|red hat" /etc/*release 2>/dev/null; then
    OS="rhel"
fi

echo "🔍 检测到操作系统: ${OS} ${OS_VERSION:-未知}"
echo ""

# ---- 部署环境选择 ----
echo "请选择部署环境："
echo "  1) 测试环境（Ubuntu 20.04）— 推荐先在此部署测试"
echo "  2) 生产环境（RHEL 8.9）"
echo ""
read -p "请输入选项 (1/2): " DEPLOY_ENV
echo ""

case $DEPLOY_ENV in
    1)
        echo "=========================================="
        echo "  🧪 测试环境部署模式"
        echo "=========================================="
        echo ""
        if [ "$OS" != "ubuntu" ]; then
            echo "⚠️  注意：当前服务器不是 Ubuntu 系统。"
            echo "   但脚本仍然可以继续，请确保 Docker 环境正常。"
            echo ""
        fi
        ;;
    2)
        echo "=========================================="
        echo "  🏭 生产环境部署模式"
        echo "=========================================="
        echo ""
        if [ "$OS" != "rhel" ] && [ "$OS" != "centos" ]; then
            echo "⚠️  注意：当前服务器不是 RHEL/CentOS 系统。"
            echo "   但脚本仍然可以继续，请确保 Docker 环境正常。"
            echo ""
        fi
        ;;
    *)
        echo "❌ 无效选项，默认为测试环境模式"
        DEPLOY_ENV=1
        ;;
esac

# 检查 Docker
if ! command -v docker &> /dev/null; then
    echo "❌ 错误: 未找到 Docker。请先安装 Docker。"
    echo ""

    if [ "$DEPLOY_ENV" = "1" ]; then
        echo "  Ubuntu 20.04 离线安装步骤："
        echo "    1. 在有网电脑上执行: bash prepare-docker-offline.sh"
        echo "       选择选项 3 → Ubuntu → 选择选项 1 → 20.04 (focal)"
        echo "    2. 将生成的 docker-offline-pkg/ 目录复制到 U 盘"
        echo "    3. 在本服务器上执行以下命令："
        echo "       # 查看 U 盘设备"
        echo "       lsblk"
        echo "       # 挂载 U 盘（假设设备是 /dev/sdb1）"
        echo "       sudo mkdir -p /mnt/usb"
        echo "       sudo mount /dev/sdb1 /mnt/usb"
        echo "       # 复制 Docker 离线包到本地"
        echo "       cp -r /mnt/usb/docker-offline-pkg ~/"
        echo "       cd ~/docker-offline-pkg"
        echo "       # 安装所有 deb 包"
        echo "       sudo dpkg -i *.deb"
        echo "       # 启动 Docker 服务"
        echo "       sudo systemctl start docker"
        echo "       sudo systemctl enable docker"
        echo "       # 验证安装"
        echo "       docker --version"
    else
        echo "  RHEL 8.9 离线安装步骤："
        echo "    1. 在有网电脑上执行: bash prepare-docker-offline.sh"
        echo "       选择选项 1 → RHEL 8.9 / CentOS 8"
        echo "    2. 将生成的 docker-offline-pkg/ 目录复制到 U 盘"
        echo "    3. 在本服务器上执行以下命令："
        echo "       sudo mount /dev/sdb1 /mnt/usb"
        echo "       cp -r /mnt/usb/docker-offline-pkg ~/"
        echo "       cd ~/docker-offline-pkg"
        echo "       sudo rpm -ivh *.rpm"
        echo "       如果报依赖缺失："
        echo "       sudo yum install -y yum-utils device-mapper-persistent-data lvm2"
        echo "       sudo rpm -ivh *.rpm"
        echo "       sudo systemctl start docker"
        echo "       sudo systemctl enable docker"
        echo "       docker --version"
    fi
    echo ""
    exit 1
fi

# 检查 docker compose
if ! docker compose version &> /dev/null; then
    if ! docker-compose version &> /dev/null; then
        echo "⚠️  未找到 docker compose 或 docker-compose。"
        echo "   将使用 docker run 启动容器（推荐安装 docker-compose-plugin）。"
        USE_COMPOSE=false
    else
        USE_COMPOSE=true
        COMPOSE_CMD="docker-compose"
    fi
else
    USE_COMPOSE=true
    COMPOSE_CMD="docker compose"
fi

echo "🔍 步骤 1/4: 检查 Docker 运行状态..."
if ! docker info &> /dev/null; then
    echo "❌ 错误: Docker 守护进程未运行。"
    echo "   请执行以下命令启动 Docker："
    echo "   sudo systemctl start docker"
    echo "   sudo systemctl enable docker"
    exit 1
fi
echo "✅ Docker 正常运行"
echo ""

echo "🔍 步骤 2/4: 加载 Docker 镜像..."
echo "    文件: ${IMAGE_TAR}"
echo "    ⏳ 加载镜像需要几分钟时间，请耐心等待..."
echo "    可以通过以下命令查看加载进度："
echo "    ls -lh ${IMAGE_TAR}  # 查看镜像文件大小"
echo ""

# 检查磁盘空间（镜像加载需要至少 2GB 可用空间）
AVAILABLE_SPACE=$(df . | tail -1 | awk '{print $4}')
if [ "$AVAILABLE_SPACE" -lt 2000000 ]; then
    echo "⚠️  警告: 当前磁盘可用空间不足 2GB，加载镜像可能会失败。"
    echo "   当前可用空间: $(df -h . | tail -1 | awk '{print $4}')"
    echo "   建议清理磁盘或切换到更大分区的目录。"
    echo ""
    read -p "是否继续？(y/n): " CONTINUE
    if [ "$CONTINUE" != "y" ]; then
        echo "已取消部署。"
        exit 1
    fi
fi

# 检查是否已存在同名镜像
if docker image inspect "${IMAGE_NAME}:${IMAGE_TAG}" &> /dev/null; then
    echo "⚠️  镜像 ${IMAGE_NAME}:${IMAGE_TAG} 已存在，正在覆盖..."
    docker rmi "${IMAGE_NAME}:${IMAGE_TAG}" 2>/dev/null || true
fi

# 检测文件实际格式并加载
echo "📦 检测文件格式: ${IMAGE_TAR}..."

FILE_TYPE=$(file "${IMAGE_TAR}" 2>/dev/null | head -1)
echo "    检测结果: ${FILE_TYPE}"

LOAD_START=$(date +%s)

# 根据文件格式选择加载方式，并捕获输出获取实际镜像名
LOAD_OUTPUT=""
if echo "${FILE_TYPE}" | grep -qi "gzip compressed"; then
    echo "    ✅ 检测为 gzip 压缩格式，使用 gunzip 解压后加载..."
    LOAD_OUTPUT=$(gunzip -c "${IMAGE_TAR}" | docker load 2>&1)
elif echo "${FILE_TYPE}" | grep -qi "XZ compressed"; then
    echo "    ✅ 检测为 xz 压缩格式，使用 xz 解压后加载..."
    LOAD_OUTPUT=$(xz -dc "${IMAGE_TAR}" | docker load 2>&1)
elif echo "${FILE_TYPE}" | grep -qi "POSIX tar archive\|tar archive"; then
    echo "    ✅ 检测为纯 tar 格式（未压缩），直接加载..."
    echo "    执行命令: docker load -i \"${IMAGE_TAR}\""
    LOAD_OUTPUT=$(docker load -i "${IMAGE_TAR}" 2>&1)
elif echo "${FILE_TYPE}" | grep -qi "bzip2 compressed"; then
    echo "    ✅ 检测为 bzip2 压缩格式，使用 bzip2 解压后加载..."
    LOAD_OUTPUT=$(bzip2 -dc "${IMAGE_TAR}" | docker load 2>&1)
else
    # 格式无法识别，尝试直接 docker load（Docker 会自动识别格式）
    echo "    ⚠️  无法识别格式，尝试直接加载..."
    LOAD_OUTPUT=$(docker load -i "${IMAGE_TAR}" 2>&1)
fi
echo "    加载输出: ${LOAD_OUTPUT}"

# 从 docker load 输出中提取实际镜像名
# 输出格式: "Loaded image: localhost/dsh-offline:latest" 或 "Loaded image: dsh-offline:latest"
LOADED_IMAGE=$(echo "${LOAD_OUTPUT}" | grep -oP 'Loaded image: \K\S+' | head -1)
if [ -z "$LOADED_IMAGE" ]; then
    # 如果没提取到，回退到默认名
    LOADED_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
    echo "    ⚠️  未能从输出中提取镜像名，使用默认: ${LOADED_IMAGE}"
fi
echo "    ✅ 实际镜像名: ${LOADED_IMAGE}"

LOAD_END=$(date +%s)
echo "✅ 镜像加载完成！用时: $((LOAD_END - LOAD_START)) 秒"
echo ""

# 验证镜像已加载
if ! docker image inspect "${LOADED_IMAGE}" &> /dev/null; then
    echo "❌ 错误: 镜像 ${LOADED_IMAGE} 加载失败，请检查 ${IMAGE_TAR} 文件是否损坏。"
    echo "   可以尝试重新从 U 盘复制文件。"
    exit 1
fi
echo "✅ 镜像验证成功: ${LOADED_IMAGE}"

# 如果加载的镜像名不是标准的 dsh-offline:latest，补一个 tag 别名
# （docker-compose.yml 中固定使用 dsh-offline:latest）
if [ "${LOADED_IMAGE}" != "${IMAGE_NAME}:${IMAGE_TAG}" ]; then
    echo "🔧 镜像名与标准名不一致，添加 tag 别名: ${IMAGE_NAME}:${IMAGE_TAG}"
    docker tag "${LOADED_IMAGE}" "${IMAGE_NAME}:${IMAGE_TAG}" 2>/dev/null || true
    echo "✅ 别名添加完成"
fi
echo ""

echo "🔍 步骤 3/4: 准备目录和配置..."
echo ""

# 创建必要目录
mkdir -p ./workspace
mkdir -p ./dsh-home

# 复制 settings.yaml（如果存在且目标不存在）
if [ -f settings.yaml ] && [ ! -f ./dsh-home/settings.yaml ]; then
    cp settings.yaml ./dsh-home/settings.yaml
    echo "📄 已复制 settings.yaml 到 dsh-home/"
    echo ""

    # 根据部署环境给出提示
    if [ "$DEPLOY_ENV" = "1" ]; then
        echo "⚠️  重要：请编辑 dsh-home/settings.yaml"
        echo "   将 <测试环境算力服务器IP> 替换为测试环境算力服务器的实际内网 IP"
        echo "   例如: baseURL: http://192.168.1.100:8000/v1"
        echo "   如果不需要生产环境配置，可以暂时忽略 <生产环境算力服务器IP>"
        echo ""
        echo "   编辑命令："
        echo "   vim dsh-home/settings.yaml"
        echo "   或 nano dsh-home/settings.yaml"
        echo ""
        echo "   编辑完成后保存退出，然后按回车继续。"
    else
        echo "⚠️  重要：请编辑 dsh-home/settings.yaml"
        echo "   将 <生产环境算力服务器IP> 替换为生产环境算力服务器的实际内网 IP"
        echo "   例如: baseURL: http://192.168.1.200:8000/v1"
        echo "   同时将默认模型改为生产环境的主模型："
        echo "     provider: prod-ascend-deepseek"
        echo "     model: DeepSeek-V4-Flash-w8a8-mtp"
        echo ""
        echo "   编辑命令："
        echo "   vim dsh-home/settings.yaml"
        echo "   或 nano dsh-home/settings.yaml"
        echo ""
        echo "   编辑完成后保存退出，然后按回车继续。"
    fi
    echo ""
    read -p "按 Enter 继续启动（或按 Ctrl+C 取消，编辑后再重新运行）..."
fi

echo "🔧 准备完成，目录结构如下："
ls -la "$(pwd)/workspace" 2>/dev/null | head -5
echo "  ..."
echo ""

# ---- 确保 entrypoint 脚本有执行权限（卷挂载需要） ----
chmod +x docker-entrypoint.sh 2>/dev/null || true

# ---- 第 4 步：启动容器 ----

# 自动检测服务器 IP（仅用于显示访问地址）
HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
if [ -z "$HOST_IP" ]; then
    HOST_IP="<你的服务器IP>"
    echo "⚠️  无法检测服务器 IP，请手动替换访问地址中的 IP"
fi
echo "📡 服务器 IP: ${HOST_IP}"
echo "   容器使用 host 网络模式"
echo "   DSH 绑定 127.0.0.1（安全策略限制）"
echo "   Node.js 转发 0.0.0.0:3080 → 127.0.0.1:3080"
echo ""

# 停止并删除旧容器（如果存在）
if docker ps -a --format '{{.Names}}' | grep -q '^dsh$'; then
    echo "⚠️  发现已存在的 dsh 容器，正在停止并删除..."
    docker stop dsh 2>/dev/null || true
    docker rm dsh 2>/dev/null || true
fi

if [ "$USE_COMPOSE" = true ] && [ -f docker-compose.yml ]; then
    echo "📋 使用 Docker Compose 启动..."
    $COMPOSE_CMD up -d
    echo ""
    echo "✅ 启动成功！"
    echo "   访问地址: http://${HOST_IP}:3080"
    echo "   查看日志: $COMPOSE_CMD logs -f"
    echo "   停止服务: $COMPOSE_CMD down"
else
    echo "📋 使用 docker run 启动（--network host 模式）..."
    docker run -d \
        --name dsh \
        --restart unless-stopped \
        --network host \
        -e DSH_ARGS="--host 127.0.0.1 --port 3080" \
        -v "$(pwd)/workspace:/workspace" \
        -v "$(pwd)/dsh-home:/root/.dsh" \
        -v "$(pwd)/docker-entrypoint.sh:/usr/local/bin/docker-entrypoint.sh" \
        "${LOADED_IMAGE}"
    echo ""
    echo "✅ 启动成功！"
    echo "   访问地址: http://${HOST_IP}:3080"
    echo "   查看日志: docker logs -f dsh"
    echo "   停止服务: docker stop dsh"
fi

echo ""
echo "=========================================="
echo "  🎉 部署完成！"
echo "=========================================="
echo ""
echo "📌 访问地址: http://${HOST_IP}:3080"
echo "   或本地访问: http://localhost:3080"
echo ""

if [ "$DEPLOY_ENV" = "1" ]; then
    echo "📌 测试环境 — 下一步操作："
    echo "   1. 打开浏览器访问上述地址"
    echo "   2. 进入 设置 → 模型，确认以下模型已配置："
    echo "      - test-ascend-deepseek → DeepSeek-R1-Distill-Llama-70B"
    echo "      - test-ascend-qwen     → Qwen3-32B"
    echo "      - test-ascend-qwen-vl  → Qwen3-VL-30B-A3B-Instruct"
    echo "   3. 选择默认模型为 DeepSeek-R1-Distill-Llama-70B"
    echo "   4. 新建工作区，开始测试！"
    echo ""
    echo "📌 Ubuntu 20.04 防火墙（如果需要远程访问）："
    echo "   sudo ufw allow 3080/tcp"
    echo "   sudo ufw status"
else
    echo "📌 生产环境 — 下一步操作："
    echo "   1. 打开浏览器访问上述地址"
    echo "   2. 进入 设置 → 模型，确认以下模型已配置："
    echo "      - prod-ascend-deepseek → DeepSeek-V4-Flash-w8a8-mtp"
    echo "      - prod-ascend-qwen-vl  → Qwen3-VL-30B-A3B-Instruct"
    echo "      - prod-ascend-ocr      → PaddleOCR-VL-0.9B"
    echo "      - prod-ascend-embedding→ Qwen3-VL-Embedding-8B"
    echo "      - prod-ascend-reranker → Qwen3-VL-Reranker-8B"
    echo "   3. 选择默认模型为 DeepSeek-V4-Flash-w8a8-mtp"
    echo "   4. 新建工作区，开始使用！"
    echo ""
    echo "📌 RHEL 8.9 防火墙（如果需要远程访问）："
    echo "   sudo firewall-cmd --add-port=3080/tcp --permanent"
    echo "   sudo firewall-cmd --reload"
    echo "   sudo firewall-cmd --list-ports"
fi
echo ""
echo "📌 验证模型连接："
echo "   curl http://<算力服务器IP>:8000/v1/models"
echo "   docker exec dsh curl -s http://<算力服务器IP>:8000/v1/models"
echo ""
echo "📌 常用命令:"
echo "   docker logs -f dsh          # 实时查看日志（按 Ctrl+C 退出）"
echo "   docker logs dsh             # 查看历史日志"
echo "   docker restart dsh          # 重启容器"
echo "   docker stop dsh             # 停止容器"
echo "   docker start dsh            # 启动已停止的容器"
echo "   docker exec -it dsh bash    # 进入容器内部"
echo "   docker stats dsh            # 查看容器资源占用"
echo "   docker ps -a | grep dsh     # 查看容器状态"