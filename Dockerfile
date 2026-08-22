# ============================================================================
# DeepSeek Harness (DSH) 离线部署 Dockerfile
# 使用 Debian bookworm-slim 基础镜像（glibc，兼容 sharp/koffi 等原生模块）
# 架构: linux/amd64 (x86_64) — 适配 RHEL 8.9 / Ubuntu 20.04 虚拟化服务器
#
# 构建方法（在有网电脑上）：
#   docker build -t dsh-offline:latest .
#   或执行: bash build-dsh-image.sh
# ============================================================================

FROM debian:bookworm-slim

LABEL description="DeepSeek Harness (DSH) - 完全离线部署版 (glibc)"
LABEL maintainer="DeepSeek AI"
LABEL version="0.1.0-rc.7"

# 安装 Node.js 22（使用预编译的 node-v22.19.0-linux-x64 二进制包）
COPY node-v22.19.0-linux-x64.tar.xz /tmp/
RUN tar -xf /tmp/node-v22.19.0-linux-x64.tar.xz -C /usr/local/ --strip-components=1 && \
    rm -f /tmp/node-v22.19.0-linux-x64.tar.xz && \
    ln -sf /usr/local/bin/node /usr/local/bin/nodejs && \
    node --version && \
    npm --version

# 安装 pnpm
COPY pnpm-linux-x64 /usr/local/bin/pnpm
RUN chmod +x /usr/local/bin/pnpm && \
    pnpm --version

# 安装 DSH 所需的系统依赖（glibc 兼容层、sharp 所需库等）
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        python3 \
        make \
        g++ \
        libvips-dev \
        && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 复制 DSH 包并安装
# --include=optional 是关键：sharp 的预编译二进制 @img/sharp-linux-x64 是 optional 依赖
# 不加这个参数，npm 不会下载它，sharp 启动时会崩溃
COPY deepseek-ai-dsh-0.1.0-rc.7.tgz /tmp/
RUN mkdir -p /tmp/dsh && \
    tar -xzf /tmp/deepseek-ai-dsh-0.1.0-rc.7.tgz -C /tmp/dsh && \
    mkdir -p /app && \
    cp -r /tmp/dsh/package/* /app/ && \
    rm -rf /tmp/dsh /tmp/deepseek-ai-dsh-0.1.0-rc.7.tgz && \
    cd /app && \
    npm install -g . --include=optional && \
    npm cache clean --force && \
    node -e "require('/usr/lib/node_modules/@deepseek-ai/dsh/node_modules/sharp'); console.log('✅ sharp 原生模块加载正常')"

# 复制配置文件
COPY settings.yaml /root/.dsh/settings.yaml
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENV DSH_HOME=/root/.dsh
ENV DSH_ARGS="--host 127.0.0.1 --port 3080"

# 暴露 DSH Web UI 默认端口
EXPOSE 3080

WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["web"]