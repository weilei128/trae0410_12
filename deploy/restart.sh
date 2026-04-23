#!/bin/bash

set -e

PROJECT_PORT=10011
BACKEND_PORT=100110
SERVER_IP="49.235.161.106"
SERVER_USER="root"
SSH_PORT=22
BASE_DIR="/opt/blog-instance-${PROJECT_PORT}"
JAR_NAME="todo-app.jar"

echo "======================================"
echo "一键重启服务 - 端口 ${PROJECT_PORT}"
echo "======================================"

echo "正在重启后端服务..."
ssh -p ${SSH_PORT} ${SERVER_USER}@${SERVER_IP} "bash -s" << EOF
PID_FILE="${BASE_DIR}/backend/app.pid"
echo "停止后端服务..."
if [ -f "\${PID_FILE}" ]; then
    PID=\$(cat "\${PID_FILE}")
    if kill -0 \${PID} 2>/dev/null; then
        echo "终止进程 PID: \${PID}"
        kill -15 \${PID}
        sleep 3
        kill -9 \${PID} 2>/dev/null || true
    fi
    rm -f "\${PID_FILE}"
fi

echo "清理端口 ${BACKEND_PORT} ..."
PIDS=\$(lsof -ti:${BACKEND_PORT} 2>/dev/null || echo "")
if [ -n "\${PIDS}" ]; then
    kill -9 \${PIDS} 2>/dev/null || true
fi

echo "启动后端服务..."
cd ${BASE_DIR}/backend
nohup java -jar -Dserver.port=${BACKEND_PORT} ${JAR_NAME} > ${BASE_DIR}/logs/backend.log 2>&1 &
echo \$! > ${BASE_DIR}/backend/app.pid
echo "后端服务已启动，PID: \$!"
EOF

echo "重启Nginx..."
ssh -p ${SSH_PORT} ${SERVER_USER}@${SERVER_IP} "systemctl reload nginx 2>/dev/null || service nginx reload 2>/dev/null || nginx -s reload 2>/dev/null || true"

echo "等待服务启动..."
sleep 8

echo "执行健康检查..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "${SCRIPT_DIR}/health-check.sh"

echo "======================================"
echo "服务重启完成!"
echo "======================================"
