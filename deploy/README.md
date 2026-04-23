# 博客项目部署脚本 - 端口10013实例

## 部署架构

```
┌─────────────────────────────────────────────────────────────┐
│                        本地开发机                            │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │   backend/   │    │  frontend/   │    │  deploy/     │  │
│  │  (Java源码)   │    │  (Vue源码)   │    │ (部署脚本)    │  │
│  └──────────────┘    └──────────────┘    └──────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ SSH + rsync 上传源码
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    服务器 (49.235.161.106)                   │
│  ┌────────────────────────────────────────────────────────┐ │
│  │           /opt/blog-app/10013/ (完全隔离目录)           │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │ │
│  │  │  backend/   │  │  frontend/  │  │    logs/    │    │ │
│  │  │  (JAR包)    │  │  (dist文件) │  │  (运行日志) │    │ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘    │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │ │
│  │  │   nginx/    │  │   backup/   │  │   source/   │    │ │
│  │  │ (Nginx配置) │  │  (版本备份) │  │  (源码目录) │    │ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘    │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## 前置要求

### 1. 配置SSH密钥

确保本地有SSH密钥，且公钥已添加到服务器：

```bash
# 生成密钥（如果没有）
ssh-keygen -t rsa -b 4096

# 复制公钥到服务器
ssh-copy-id -p 22 root@49.235.161.106
```

### 2. 服务器环境要求

服务器需要预装以下软件：
- Java 8+ (用于运行后端)
- Maven (用于构建后端)
- Node.js 16+ 和 npm (用于构建前端)
- Nginx (用于前端服务)

## 快速开始

### Windows 用户

使用 Git Bash 或 WSL 执行：

```bash
cd deploy
bash deploy-local.sh deploy
```

### Linux/Mac 用户

```bash
cd deploy
bash deploy-local.sh deploy
```

## 命令说明

### 完整部署
```bash
bash deploy-local.sh deploy
```
执行流程：
1. 检查SSH连接
2. 上传前后端源码到服务器
3. 在服务器上构建后端（Maven）
4. 在服务器上构建前端（npm）
5. 查杀占用10013端口的进程（仅本项目）
6. 启动后端服务
7. 配置Nginx
8. 执行健康检查
9. 记录部署结果

### 运维命令

```bash
# 一键重启
bash deploy-local.sh restart

# 停止服务
bash deploy-local.sh stop

# 启动服务
bash deploy-local.sh start

# 查看状态
bash deploy-local.sh status

# 查看日志
bash deploy-local.sh logs backend 100    # 后端日志
bash deploy-local.sh logs nginx 50       # Nginx日志

# 健康检查
bash deploy-local.sh health

# 回滚到上一个版本
bash deploy-local.sh rollback
```

## 核心特性

### 1. 端口严格隔离
- 仅使用端口 **10013**
- 查杀进程时严格验证进程归属（通过检查进程命令行是否包含 `todo-app` 或 `java.*10013`）
- 不会误杀其他端口（10011/10012）的服务

### 2. 目录完全隔离
```
/opt/blog-app/10013/
├── backend/           # 后端JAR包
├── frontend/          # 前端dist文件
├── logs/              # 运行日志
│   ├── app.log        # 后端应用日志
│   ├── nginx_access.log
│   └── nginx_error.log
├── nginx/             # Nginx配置
│   └── blog-10013.conf
├── backup/            # 版本备份
├── source/            # 源码目录
│   ├── backend/       # 后端源码
│   └── frontend/      # 前端源码
└── .deploy_result     # 部署结果记录
```

### 3. 自动健康检查
部署后自动验证：
- 后端API: `http://localhost:10013/api/todos`
- 前端页面: `http://localhost:10013/index.html`

### 4. 一键回滚
每次部署前自动备份JAR包，支持快速回滚：
```bash
bash deploy-local.sh rollback
```

### 5. 部署结果固化
每次部署结果记录在服务器上：
```bash
# 在服务器上查看
cat /opt/blog-app/10013/.deploy_result
```

## 访问地址

部署成功后，可通过以下地址访问：

- **前端页面**: http://49.235.161.106:10013
- **后端API**: http://49.235.161.106:10013/api/todos

## 故障排查

### 1. SSH连接失败
```bash
# 测试SSH连接
ssh -p 22 root@49.235.161.106

# 如果失败，检查密钥
ssh-copy-id -p 22 root@49.235.161.106
```

### 2. 部署失败查看日志
```bash
# 查看后端日志
bash deploy-local.sh logs backend 200

# 查看Nginx日志
bash deploy-local.sh logs nginx 100
```

### 3. 端口被占用
```bash
# 在服务器上手动查杀
ssh root@49.235.161.106 "lsof -i:10013 | grep LISTEN"
ssh root@49.235.161.106 "kill -9 <PID>"
```

### 4. 回滚操作
```bash
# 如果新版本有问题，快速回滚
bash deploy-local.sh rollback
```

## 注意事项

1. **严禁操作其他端口**：本脚本严格限定只操作10013端口，不会影响10011/10012实例
2. **进程安全查杀**：通过检查进程命令行确认进程归属，避免误杀
3. **完全隔离**：所有文件按端口10013独立存放，与其他实例无冲突
