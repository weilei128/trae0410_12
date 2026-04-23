#!/bin/bash

set -e

PROJECT_PORT=10011
SERVER_IP="49.235.161.106"
SERVER_USER="root"
SSH_PORT=22
BASE_DIR="/opt/blog-instance-${PROJECT_PORT}"

echo "======================================"
echo "博客系统部署脚本 - 端口 ${PROJECT_PORT}"
echo "======================================"

DEPLOY_START_TIME=$(date +%s)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

echo "[1/7] 初始化部署环境，创建目录结构..."
ssh -p ${SSH_PORT} ${SERVER_USER}@${SERVER_IP} "bash -s" << EOF
mkdir -p ${BASE_DIR}/backend
mkdir -p ${BASE_DIR}/frontend/dist
mkdir -p ${BASE_DIR}/logs
mkdir -p ${BASE_DIR}/nginx
mkdir -p ${BASE_DIR}/backup
mkdir -p ${BASE_DIR}/script
echo "目录结构创建完成: ${BASE_DIR}"
EOF

echo "[2/7] 安全查杀端口 ${PROJECT_PORT} 进程..."
ssh -p ${SSH_PORT} ${SERVER_USER}@${SERVER_IP} "bash -s" << 'EOF'
PORT=10011
echo "检查端口 ${PORT} 占用情况..."
PIDS=$(lsof -ti:${PORT} 2>/dev/null || echo "")
if [ -n "${PIDS}" ]; then
    echo "发现占用端口 ${PORT} 的进程: ${PIDS}"
    for PID in ${PIDS}; do
        PROCESS_NAME=$(ps -p ${PID} -o comm= 2>/dev/null || echo "unknown")
        echo "正在终止进程 ${PID} (${PROCESS_NAME})..."
        kill -15 ${PID} 2>/dev/null || true
        sleep 1
        if kill -0 ${PID} 2>/dev/null; then
            echo "进程未响应，强制终止..."
            kill -9 ${PID} 2>/dev/null || true
        fi
    done
    echo "端口 ${PORT} 已清理完成"
else
    echo "端口 ${PORT} 未被占用"
fi
EOF

echo "[3/7] 上传部署工具脚本到服务器..."
scp -P ${SSH_PORT} "${SCRIPT_DIR}/deploy-backend.sh" "${SCRIPT_DIR}/deploy-frontend.sh" "${SCRIPT_DIR}/health-check.sh" "${SCRIPT_DIR}/restart.sh" "${SCRIPT_DIR}/rollback.sh" ${SERVER_USER}@${SERVER_IP}:${BASE_DIR}/script/
ssh -p ${SSH_PORT} ${SERVER_USER}@${SERVER_IP} "chmod +x ${BASE_DIR}/script/*.sh"

echo "[4/7] 部署后端服务..."
bash "${SCRIPT_DIR}/deploy-backend.sh"

echo "[5/7] 部署前端服务..."
bash "${SCRIPT_DIR}/deploy-frontend.sh"

echo "[6/7] 配置Nginx..."
ssh -p ${SSH_PORT} ${SERVER_USER}@${SERVER_IP} "bash -s" << EOF
if ! command -v nginx &> /dev/null; then
    echo "Nginx未安装，正在安装..."
    apt-get update && apt-get install -y nginx || yum install -y nginx
fi

mkdir -p /etc/nginx/conf.d/

cat > /etc/nginx/conf.d/blog-${PROJECT_PORT}.conf << 'NGINXCONF'
server {
    listen ${PROJECT_PORT};
    server_name _;

    location / {
        root ${BASE_DIR}/frontend/dist;
        index index.html index.htm;
        try_files \$uri \$uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:${PROJECT_PORT}0;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINXCONF

nginx -t && systemctl reload nginx || echo "Nginx配置已更新，请手动重载"
EOF

echo "[7/7] 执行健康检查..."
sleep 5
bash "${SCRIPT_DIR}/health-check.sh"

DEPLOY_END_TIME=$(date +%s)
DEPLOY_DURATION=$((DEPLOY_END_TIME - DEPLOY_START_TIME))
DEPLOY_DATE=$(date "+%Y-%m-%d %H:%M:%S")

ssh -p ${SSH_PORT} ${SERVER_USER}@${SERVER_IP} "cat > ${BASE_DIR}/deploy-history.log << EOF
======================================
部署时间: ${DEPLOY_DATE}
部署耗时: ${DEPLOY_DURATION} 秒
部署端口: ${PROJECT_PORT}
部署状态: 完成
======================================
EOF"

echo "======================================"
echo "部署完成！"
echo "部署时间: ${DEPLOY_DATE}"
echo "部署耗时: ${DEPLOY_DURATION} 秒"
echo "前端访问: http://${SERVER_IP}:${PROJECT_PORT}"
echo "后端接口: http://${SERVER_IP}:${PROJECT_PORT}0/api/todo"
echo "服务器目录: ${BASE_DIR}"
echo "======================================"
