# 内网实用工具栈 — 部署指南

> 适用于完全物理隔离的内网环境，所有工具通过 Docker 部署，支持离线导入。

---

## 工具清单

| 序号 | 工具 | 端口 | 用途 | 轻量程度 |
|------|------|------|------|---------|
| 1 | **Portainer CE** | 9443/9000 | Docker 容器可视化管理面板 | 中 |
| 2 | **Gitea** | 3000/2222 | 轻量级 Git 代码托管平台 | 较轻 |
| 3 | **Grafana** | 3001 | 监控可视化面板 | 中 |
| 4 | **Prometheus** | 9090 | 指标采集与存储 | 中 |
| 5 | **Node Exporter** | 9100 | 主机资源指标采集 (CPU/内存/磁盘) | 轻 |
| 6 | **cAdvisor** | 8080 | Docker 容器指标采集 | 轻 |
| 7 | **Loki** | 3100 | 轻量级日志存储 | 较轻 |
| 8 | **Promtail** | - | 日志采集代理 | 轻 |
| 9 | **Nginx Proxy Manager** | 80/81/443 | 反向代理/端口转发管理 | 较轻 |

---

## 架构总览

```
内网服务器
  ├── Portainer (9443)    — 统一管理所有容器
  ├── Gitea (3000)        — 代码托管 + CI/CD
  ├── Grafana (3001)      — 统一监控面板
  │   ├── Prometheus (9090)  — 系统指标
  │   │   ├── Node Exporter (9100) — 主机资源
  │   │   └── cAdvisor (8080)      — 容器资源
  │   └── Loki (3100)        — 日志存储
  │       └── Promtail         — 日志采集
  └── Nginx Proxy Manager (81) — 反向代理统一入口
```

---

## 部署步骤

### 第一步：在有网电脑上准备镜像

```bash
# 1. 拉取所有镜像
docker compose -f docker-compose.tools.yml pull

# 2. 导出所有镜像为一个 tar 包
docker save \
  portainer/portainer-ce:latest \
  gitea/gitea:latest \
  grafana/grafana:latest \
  prom/prometheus:latest \
  prom/node-exporter:latest \
  gcr.io/cadvisor/cadvisor:latest \
  grafana/loki:latest \
  grafana/promtail:latest \
  jc21/nginx-proxy-manager:latest \
  -o intranet-tools-images.tar

# 3. 查看大小
ls -lh intranet-tools-images.tar
# 约 2-3GB

# 4. 压缩
gzip intranet-tools-images.tar
```

### 第二步：传输到内网

将以下文件通过 U 盘拷贝到内网服务器：
- `docker-compose.tools.yml`
- `intranet-tools-images.tar.gz`
- `prometheus.yml`
- `promtail-config.yml`

### 第三步：内网加载镜像

```bash
# 加载所有镜像
gunzip -c intranet-tools-images.tar.gz | docker load

# 确认镜像已加载
docker images | grep -E 'portainer|gitea|grafana|prometheus|node-exporter|cadvisor|loki|promtail|nginx-proxy'
```

### 第四步：准备配置文件

```bash
# 创建数据目录
mkdir -p data/{portainer,gitea,grafana,prometheus/config,prometheus/data,loki,promtail,npm,npm-letsencrypt}

# 复制配置文件
cp prometheus.yml data/prometheus/config/
cp promtail-config.yml data/promtail/config.yml
```

### 第五步：启动所有工具

```bash
# 启动
docker compose -f docker-compose.tools.yml up -d

# 查看状态
docker compose -f docker-compose.tools.yml ps

# 查看日志
docker compose -f docker-compose.tools.yml logs -f
```

### 第六步：初始化配置

#### Portainer
1. 访问 `http://<服务器IP>:9443`
2. 创建管理员账户
3. 选择 Get Started 连接本地 Docker

#### Gitea
1. 访问 `http://<服务器IP>:3000`
2. 首次访问会进入安装页面
3. 数据库选择 SQLite3（轻量，无需额外安装）
4. 设置管理员账户

#### Grafana
1. 访问 `http://<服务器IP>:3001`
2. 默认账户：admin / admin（首次登录会要求改密码）
3. 添加数据源：
   - Prometheus: URL 填 `http://prometheus:9090`
   - Loki: URL 填 `http://loki:3100`
4. 导入 Dashboard（Dashboards -> Import）：
   - Node Exporter Full: ID `1860`
   - Docker Monitoring: ID `193`

#### Nginx Proxy Manager
1. 访问 `http://<服务器IP>:81`
2. 默认账户：admin@example.com / changeme
3. 添加代理规则，将各服务统一到 80 端口

---

## 端口冲突注意

如果 DSH 也部署在同一台服务器上：
- DSH 使用 `3080` 端口 — 不冲突
- Gitea 使用 `3000` 端口
- Grafana 映射到 `3001` 避免冲突

如果端口仍冲突，修改 `docker-compose.tools.yml` 中的端口映射。

---

## 常用运维命令

```bash
# 启动所有工具
docker compose -f docker-compose.tools.yml up -d

# 停止所有工具
docker compose -f docker-compose.tools.yml down

# 重启某个工具
docker compose -f docker-compose.tools.yml restart grafana

# 查看某个工具日志
docker compose -f docker-compose.tools.yml logs -f prometheus

# 查看资源占用
docker stats portainer gitea grafana prometheus loki
```

---

## Token 监控方案

Grafana 配合 Prometheus 可以监控 API Token 使用量：

1. 在 DSH 的 vLLM 服务上启用 metrics 接口
2. 在 `prometheus.yml` 中添加采集任务：
   ```yaml
   - job_name: 'vllm'
     static_configs:
       - targets: ['<算力服务器IP>:8000']
   ```
3. 在 Grafana 中创建 Token 使用量 Dashboard
4. 设置告警规则（当 Token 使用量超过阈值时触发）
