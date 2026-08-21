#!/bin/bash
set -e

# ============================================================================
# Docker 离线安装包准备脚本
# 在【有网络的电脑】上运行，下载 Docker 的离线安装包
# 适用于 RHEL 8.9 / CentOS / Ubuntu 内网服务器
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "  Docker 离线安装包准备脚本"
echo "=========================================="
echo ""
echo "请选择你的内网服务器操作系统："
echo "  1) Red Hat Enterprise Linux 8.9 / CentOS 8 (rpm)"
echo "  2) Red Hat Enterprise Linux 9 / CentOS 9 (rpm)"
echo "  3) Ubuntu 20.04/22.04/24.04 (deb)"
echo "  4) 通用静态二进制（无需安装，直接运行）"
echo ""

read -p "请输入选项 (1/2/3/4): " OS_CHOICE

DOCKER_DIR="docker-offline-pkg"
rm -rf "$DOCKER_DIR"
mkdir -p "$DOCKER_DIR"

# 选择下载源
echo ""
echo "请选择下载镜像源："
echo "  1) Docker 官方源（download.docker.com，默认推荐）"
echo "  2) 华为云镜像站（mirrors.huaweicloud.com，国内速度快）"
echo "  3) 阿里云镜像站（mirrors.aliyun.com，国内速度快）"
echo ""
read -p "请输入选项 (1/2/3): " MIRROR_CHOICE

case $MIRROR_CHOICE in
    1) BASE_MIRROR="https://download.docker.com" ;;
    2) BASE_MIRROR="https://mirrors.huaweicloud.com/docker-ce" ;;
    3) BASE_MIRROR="https://mirrors.aliyun.com/docker-ce" ;;
    *) BASE_MIRROR="https://download.docker.com" ;;
esac

case $OS_CHOICE in
    1)
        echo ""
        echo "📦 下载 RHEL 8.9 / CentOS 8 Docker 离线安装包..."
        echo "    镜像源: ${BASE_MIRROR}"
        echo ""

        # Docker CE 官方 RPM 仓库（RHEL 8 使用 centos 8 的 repo）
        DOCKER_RPM_URL="${BASE_MIRROR}/linux/centos"
        ARCH="x86_64"
        RELEASE="8"

        # 下载策略：优先使用 yumdownloader（如果有）
        if command -v yumdownloader &> /dev/null; then
            echo "    使用 yumdownloader 下载 RPM 包..."
            # 先添加 docker 仓库
            yum-config-manager --add-repo "${DOCKER_RPM_URL}/docker-ce.repo" 2>/dev/null || true
            yumdownloader --resolve --destdir="$DOCKER_DIR" \
                docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null
        fi

        # 使用 curl 直接下载
        echo "    从仓库下载 RPM 包..."
        BASE_URL="${DOCKER_RPM_URL}/${RELEASE}/${ARCH}/stable/Packages"

        # 下载 docker-ce
        PKG=$(curl -sfL "${BASE_URL}/" | grep -oP 'docker-ce-[0-9][^"]+\.rpm' | sort -V | tail -1)
        [ -n "$PKG" ] && curl -sL "${BASE_URL}/${PKG}" -o "${DOCKER_DIR}/${PKG}" && echo "    ✅ 下载: ${PKG}"

        # 下载 docker-ce-cli
        PKG=$(curl -sfL "${BASE_URL}/" | grep -oP 'docker-ce-cli-[0-9][^"]+\.rpm' | sort -V | tail -1)
        [ -n "$PKG" ] && curl -sL "${BASE_URL}/${PKG}" -o "${DOCKER_DIR}/${PKG}" && echo "    ✅ 下载: ${PKG}"

        # 下载 containerd.io
        PKG=$(curl -sfL "${BASE_URL}/" | grep -oP 'containerd\.io-[0-9][^"]+\.rpm' | sort -V | tail -1)
        [ -n "$PKG" ] && curl -sL "${BASE_URL}/${PKG}" -o "${DOCKER_DIR}/${PKG}" && echo "    ✅ 下载: ${PKG}"

        # 下载 docker-buildx-plugin
        PKG=$(curl -sfL "${BASE_URL}/" | grep -oP 'docker-buildx-plugin-[0-9][^"]+\.rpm' | sort -V | tail -1)
        [ -n "$PKG" ] && curl -sL "${BASE_URL}/${PKG}" -o "${DOCKER_DIR}/${PKG}" && echo "    ✅ 下载: ${PKG}"

        # 下载 docker-compose-plugin
        PKG=$(curl -sfL "${BASE_URL}/" | grep -oP 'docker-compose-plugin-[0-9][^"]+\.rpm' | sort -V | tail -1)
        [ -n "$PKG" ] && curl -sL "${BASE_URL}/${PKG}" -o "${DOCKER_DIR}/${PKG}" && echo "    ✅ 下载: ${PKG}"

        # 下载 docker-ce-source（可选）
        PKG=$(curl -sfL "${BASE_URL}/" | grep -oP 'docker-ce-source-[^"]+\.rpm' | sort -V | tail -1)
        [ -n "$PKG" ] && curl -sL "${BASE_URL}/${PKG}" -o "${DOCKER_DIR}/${PKG}" && echo "    ✅ 下载: ${PKG}"

        INSTALL_GUIDE="sudo rpm -ivh *.rpm"
        ;;

    2)
        echo ""
        echo "📦 下载 RHEL 9 / CentOS 9 Docker 离线安装包..."
        echo "    镜像源: ${BASE_MIRROR}"
        echo ""

        ARCH="x86_64"
        RELEASE="9"
        BASE_URL="${BASE_MIRROR}/linux/centos/${RELEASE}/${ARCH}/stable/Packages"

        # 下载 docker-ce
        PKG=$(curl -sfL "${BASE_URL}/" | grep -oP 'docker-ce-[0-9][^"]+\.rpm' | sort -V | tail -1)
        [ -n "$PKG" ] && curl -sL "${BASE_URL}/${PKG}" -o "${DOCKER_DIR}/${PKG}" && echo "    ✅ 下载: ${PKG}"

        PKG=$(curl -sfL "${BASE_URL}/" | grep -oP 'docker-ce-cli-[0-9][^"]+\.rpm' | sort -V | tail -1)
        [ -n "$PKG" ] && curl -sL "${BASE_URL}/${PKG}" -o "${DOCKER_DIR}/${PKG}" && echo "    ✅ 下载: ${PKG}"

        PKG=$(curl -sfL "${BASE_URL}/" | grep -oP 'containerd\.io-[0-9][^"]+\.rpm' | sort -V | tail -1)
        [ -n "$PKG" ] && curl -sL "${BASE_URL}/${PKG}" -o "${DOCKER_DIR}/${PKG}" && echo "    ✅ 下载: ${PKG}"

        PKG=$(curl -sfL "${BASE_URL}/" | grep -oP 'docker-buildx-plugin-[0-9][^"]+\.rpm' | sort -V | tail -1)
        [ -n "$PKG" ] && curl -sL "${BASE_URL}/${PKG}" -o "${DOCKER_DIR}/${PKG}" && echo "    ✅ 下载: ${PKG}"

        PKG=$(curl -sfL "${BASE_URL}/" | grep -oP 'docker-compose-plugin-[0-9][^"]+\.rpm' | sort -V | tail -1)
        [ -n "$PKG" ] && curl -sL "${BASE_URL}/${PKG}" -o "${DOCKER_DIR}/${PKG}" && echo "    ✅ 下载: ${PKG}"

        INSTALL_GUIDE="sudo rpm -ivh *.rpm"
        ;;

    3)
        echo ""
        echo "📦 下载 Ubuntu Docker 离线安装包..."
        echo "    镜像源: ${BASE_MIRROR}"
        echo ""

        ARCH="amd64"
        # 选择 Ubuntu 版本（RHEL 用户通常在 ubuntu 上选 jammy=22.04）
        echo "请选择 Ubuntu 版本："
        echo "  1) Ubuntu 20.04 (focal)"
        echo "  2) Ubuntu 22.04 (jammy) — 推荐"
        echo "  3) Ubuntu 24.04 (noble)"
        read -p "请输入选项 (1/2/3): " UBUNTU_VER
        case $UBUNTU_VER in
            1) CODENAME="focal" ;;
            2) CODENAME="jammy" ;;
            3) CODENAME="noble" ;;
            *) CODENAME="jammy" ;;
        esac

        BASE_URL="${BASE_MIRROR}/linux/ubuntu/dists/${CODENAME}/pool/stable/${ARCH}"

        for PKG in docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; do
            VERSION=$(curl -sfL "${BASE_URL}/" | grep -oP "${PKG}_[^_]+_${ARCH}\.deb" | sort -V | tail -1)
            if [ -n "$VERSION" ]; then
                echo "    下载: $VERSION"
                curl -sL "${BASE_URL}/${VERSION}" -o "${DOCKER_DIR}/${VERSION}"
            fi
        done

        INSTALL_GUIDE="sudo dpkg -i *.deb"
        ;;

    4)
        echo ""
        echo "📦 下载 Docker 静态二进制文件..."
        echo ""

        # 下载静态二进制文件
        DOCKER_BIN_URL="${BASE_MIRROR}/linux/static/stable/x86_64"
        LATEST_TGZ=$(curl -sfL "${DOCKER_BIN_URL}/" | grep -oP 'docker-[0-9]+\.[0-9]+\.[0-9]+\.tgz' | sort -V | tail -1)

        if [ -n "$LATEST_TGZ" ]; then
            echo "    下载: ${LATEST_TGZ}"
            curl -sL "${DOCKER_BIN_URL}/${LATEST_TGZ}" -o "${DOCKER_DIR}/${LATEST_TGZ}"

            # 下载 docker-compose 插件
            COMPOSE_BASE="${BASE_MIRROR}/docker-compose"
            COMPOSE_URL="https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64"
            curl -sL "$COMPOSE_URL" -o "${DOCKER_DIR}/docker-compose"
            chmod +x "${DOCKER_DIR}/docker-compose"

            echo "    ✅ 下载完成"
        else
            echo "    ❌ 下载失败，请检查网络连接"
            exit 1
        fi

        INSTALL_GUIDE="tar -xzf docker-*.tgz && sudo cp docker/* /usr/bin/ && sudo cp docker-compose /usr/bin/"
        ;;

    *)
        echo "❌ 无效选项，退出"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo "  ✅ 下载完成！"
echo "=========================================="
echo ""
echo "离线包目录: ${DOCKER_DIR}/"
echo "总大小: $(du -sh "${DOCKER_DIR}" | cut -f1)"
echo "内容:"
ls -lh "$DOCKER_DIR"
echo ""
echo "=========================================="
echo "  📋 内网安装步骤（RHEL 8.9）"
echo "=========================================="
echo ""
echo "  1. 将 ${DOCKER_DIR}/ 目录拷贝到 U 盘"
echo "     （如果有依赖报错，需要额外下载依赖包）"
echo ""
echo "  2. 在内网虚拟化服务器上，将 U 盘复制到本地："
echo "     sudo mount /dev/sdb1 /mnt/usb"
echo "     cp -r /mnt/usb/${DOCKER_DIR} ~/"
echo "     cd ~/${DOCKER_DIR}"
echo ""
echo "  3. 安装 Docker（RHEL 8.9）："
echo "     sudo rpm -ivh *.rpm"
echo "     如果报依赖缺失，需要手动补充依赖："
echo "     sudo yum install -y yum-utils device-mapper-persistent-data lvm2"
echo "     然后重试安装。"
echo ""
echo "  4. 启动 Docker 服务："
echo "     sudo systemctl start docker"
echo "     sudo systemctl enable docker"
echo "     sudo docker --version"
echo ""
echo "  5. 验证安装："
echo "     sudo docker run hello-world"
echo "     如果无法 pull 镜像（内网环境），跳过此步即可。"
echo ""