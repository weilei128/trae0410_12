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
echo "服务快速回滚 - 端口 ${PROJECT_PORT}"
echo "======================================"

ROLLBACK_TIME=$(date "+%Y%m%d_%H%M%S")

echo "可用的备份版本:"
ssh -p ${SSH_PORT} ${SERVER_USER}@${SERVER_IP} "bash -s" << EOF
echo ""
echo "--- 后端备份列表 (最新5个) ---"
ls -lh ${BASE_DIR}/backup/*.jar.* 2>/dev/null | tail -5 || echo "无后端备份"
echo ""
echo "--- 前端备份列表 (最新5个) ---"
ls -lh ${BASE_DIR}/backup/frontend*.tar.gz 2>/dev/null | tail -5 || echo "无前端备份"
echo ""
EOF

LATEST_BACKEND=$(ssh -p ${SSH_PORT} ${SERVER_USER}@${SERVER_IP} "ls -1t ${BASE_DIR}/backup/*.jar.* 2>/dev/null | head -1")
LATEST_FRONTEND=$(ssh -p ${SSH_PORT} ${SERVER_USER}@${SERVER_IP} "ls -1t ${BASE_DIR}/backup/frontend*.tar.gz 2>/dev/null | head -1")

if [ -z "${LATEST_BACKEND}" ] && [ -z "${LATEST_FRONTEND}" ]; then
    echo "❌ 未找到任何备份文件，无法回滚"
    exit 1
fi

echo "回滚到最近的备份版本:"
echo "后端: ${LATEST_BACKEND:-无}"
echo "前端: ${LATEST_FRONTEND:-无}"
echo ""
read -p "确认执行回滚? (y/N): " -n 1 -r
echo ""
if [[ ! \$REPLY =~ ^[Yy]$ ]]; then
    echo "已取消回滚"
    exit 0
fi

echo "开始执行回滚..."

if [ -n "${LATEST_BACKEND}" ]; then
    echo "[1/2] 回滚后端服务..."
    ssh -p ${SSH_PORT} ${SERVER_USER}@${SERVER_IP} "bash -s" << EOF
echo "从备份恢复: ${LATEST_BACKEND}"
cp "${LATEST_BACKEND}" "${BASE_DIR}/backend/${JAR_NAME}"

PID_FILE="${BASE_DIR}/backend/app.pid"
if [ -f "\${PID_FILE}" ]; then
    PID=\$(cat "\${PID_FILE}")
    kill -15 \${PID} 2>/dev/null || true
    sleep 2
    kill -9 \${PID} 2>/dev/null || true
    rm -f "\${PID_FILE}"
fi

PIDS=\$(lsof -ti:${BACKEND_PORT} 2>/dev/null || echo "")
if [ -n "\${PIDS}" ]; then
    kill -9 \${PIDS} 2>/dev/null || true
fi

echo "启动回滚后的后端服务..."
cd ${BASE_DIR}/backend
nohup java -jar -Dserver.port=${BACKEND_PORT} ${JAR_NAME} > ${BASE_DIR}/logs/backend.log 2>&1 &
echo \$! > ${BASE_DIR}/backend/app.pid
echo "后端回滚完成，PID: \$!"
EOF
fi

if [ -n "${LATEST_FRONTEND}" ]; then
    echo "[2/2] 回滚前端服务..."
    ssh -p ${SSH_PORT} ${SERVER_USER}@${SERVER_IP} "bash -s" << EOF
echo "从备份恢复: ${LATEST_FRONTEND}"
cd ${BASE_DIR}/frontend
rm -rf dist
tar -xzf "${LATEST_FRONTEND}"
echo "前端回滚完成"
systemctl reload nginx 2>/dev/null || true
EOF
fi

ssh -p ${SSH_PORT} ${SERVER_USER}@${SERVER_IP} "echo '回滚完成时间: ${ROLLBACK_TIME}' >> ${BASE_DIR}/rollback-history.log"

echo "等待服务启动..."
sleep 8

echo "执行健康检查..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "${SCRIPT_DIR}/health-check.sh"

echo "======================================"
echo "回滚操作完成!"
echo "回滚时间: $(date)"
echo "======================================"
