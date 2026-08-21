#!/bin/sh
set -e

# DeepSeek Harness Docker 入口脚本
# ============================================================================
# DSH 的 webserver 插件出于安全原因，只允许绑定 127.0.0.1（本地回环）
# 我们通过 Node.js TCP 转发，让外部可以访问：
#   Node.js 转发 0.0.0.0:3080 → DSH 127.0.0.1:3080
# 配合 Docker 的 --network host 模式，不需要 iptables 端口映射
# ============================================================================

# 如果是 web 模式，启动 Web UI + 端口转发
if [ "$1" = "web" ]; then
    PORT="${DSH_PORT:-3080}"

    echo "🚀 启动 DeepSeek Harness Web UI..."
    echo "📍 DSH 内部监听: 127.0.0.1:${PORT}"
    echo "🔁 Node.js 端口转发: 0.0.0.0:${PORT} → 127.0.0.1:${PORT}"
    echo "📂 DSH 工作目录: ${DSH_HOME}"
    echo ""

    # 启动 DSH（必须绑定 127.0.0.1，DSH 安全策略限制）
    dsh web $DSH_ARGS &
    DSH_PID=$!

    # 等待 DSH 就绪
    sleep 2

    # 使用 Node.js 做 TCP 端口转发（不需要额外安装任何包，Node.js 已内置）
    # 监听 0.0.0.0，将 TCP 连接转发到 127.0.0.1
    echo "🔗 启动端口转发 (0.0.0.0:${PORT} → 127.0.0.1:${PORT})..."
    node -e "
    const net = require('net');
    const PORT = ${PORT};
    const TARGET = '127.0.0.1';

    const server = net.createServer((client) => {
        const backend = net.createConnection({ host: TARGET, port: PORT }, () => {
            client.pipe(backend);
            backend.pipe(client);
        });
        client.on('error', () => backend.destroy());
        backend.on('error', () => client.destroy());
    });

    server.listen(PORT, '0.0.0.0', () => {
        process.stdout.write('✅ 端口转发已就绪，等待连接...\n');
    });
    " &
    NODE_FWD_PID=$!

    echo "✅ 启动完成！DSH Web UI 可通过 http://<服务器IP>:${PORT} 访问"
    echo ""

    # 等待任意子进程退出
    wait
fi

# 否则直接执行用户命令
exec "$@"