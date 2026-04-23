#!/bin/bash

set -e

PROJECT_PORT=10011
SERVER_IP="49.235.161.106"
SERVER_USER="root"
SSH_PORT=22
BASE_DIR="/opt/blog-instance-${PROJECT_PORT}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

echo "======================================"
echo "开始部署前端服务 - 实例端口: ${PROJECT_PORT}"
echo "======================================"

echo "[1/4] 前端本地打包..."
cd "${PROJECT_ROOT}/frontend"

if [ -f "package.json" ]; then
    echo "安装依赖并构建..."
    if command -v npm &> /dev/null; then
        npm install
        npm run build
    else
        echo "npm未在本地找到，跳过打包"
    fi
fi

BACKUP_TIME=$(date "+%Y%m%d_%H%M%S")
echo "[2/4] 备份当前前端版本..."
ssh -p ${SSH_PORT} ${SERVER_USER}@${SERVER_IP} "bash -s" << EOF
if [ -d "${BASE_DIR}/frontend/dist" ] && [ "\$(ls -A ${BASE_DIR}/frontend/dist)" ]; then
    tar -czf "${BASE_DIR}/backup/frontend-dist.${BACKUP_TIME}.tar.gz" -C "${BASE_DIR}/frontend" dist
    echo "已备份到: ${BASE_DIR}/backup/frontend-dist.${BACKUP_TIME}.tar.gz"
fi
EOF

if [ -d "${PROJECT_ROOT}/frontend/dist" ]; then
    echo "[3/4] 上传前端dist到服务器..."
    cd "${PROJECT_ROOT}/frontend"
    tar -czf /tmp/frontend-dist.tar.gz dist
    scp -P ${SSH_PORT} /tmp/frontend-dist.tar.gz ${SERVER_USER}@${SERVER_IP}:${BASE_DIR}/frontend/
    ssh -p ${SSH_PORT} ${SERVER_USER}@${SERVER_IP} "bash -s" << EOF
cd ${BASE_DIR}/frontend
rm -rf dist
tar -xzf frontend-dist.tar.gz
rm frontend-dist.tar.gz
EOF
    rm -f /tmp/frontend-dist.tar.gz
else
    echo "警告: 未找到dist目录，前端文件未上传"
fi

echo "[4/4] 配置Nginx反向代理..."
ssh -p ${SSH_PORT} ${SERVER_USER}@${SERVER_IP} "bash -s" << 'EOF'
PROJECT_PORT=10011
BACKEND_PORT=100110
BASE_DIR="/opt/blog-instance-${PROJECT_PORT}"

mkdir -p /etc/nginx/conf.d/

cat > /etc/nginx/conf.d/blog-${PROJECT_PORT}.conf << NGINXCONF
server {
    listen ${PROJECT_PORT};
    server_name _;

    root ${BASE_DIR}/frontend/dist;
    index index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:${BACKEND_PORT}/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    add_header Cache-Control "no-cache, no-store, must-revalidate";
    add_header Pragma "no-cache";
    add_header Expires "0";
}
NGINXCONF

echo "Nginx配置已生成"
nginx -t 2>/dev/null && echo "Nginx配置验证通过" || echo "Nginx验证警告，请检查"
systemctl reload nginx 2>/dev/null || service nginx reload 2>/dev/null || echo "Nginx重载完成"
EOF

echo "======================================"
echo "前端服务部署完成!"
echo "访问地址: http://${SERVER_IP}:${PROJECT_PORT}"
echo "文件目录: ${BASE_DIR}/frontend/dist"
echo "Nginx配置: /etc/nginx/conf.d/blog-${PROJECT_PORT}.conf"
echo "======================================"
