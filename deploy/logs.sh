#!/bin/bash

PROJECT_PORT=10011
SERVER_IP="49.235.161.106"
SERVER_USER="root"
SSH_PORT=22
BASE_DIR="/opt/blog-instance-${PROJECT_PORT}"

echo "======================================"
echo "查看实时日志 - 端口 ${PROJECT_PORT}"
echo "======================================"
echo "1. 后端运行日志"
echo "2. Nginx访问日志"
echo "3. 部署历史"
echo "======================================"

read -p "请选择 [1-3]: " choice

case ${choice} in
    1)
        echo "后端实时日志 (Ctrl+C退出)..."
        ssh -t -p ${SSH_PORT} ${SERVER_USER}@${SERVER_IP} "tail -f ${BASE_DIR}/logs/backend.log"
        ;;
    2)
        echo "Nginx访问日志..."
        ssh -t -p ${SSH_PORT} ${SERVER_USER}@${SERVER_IP} "tail -f /var/log/nginx/access.log"
        ;;
    3)
        echo "部署历史记录..."
        ssh -p ${SSH_PORT} ${SERVER_USER}@${SERVER_IP} "cat ${BASE_DIR}/deploy-history.log 2>/dev/null || echo '无部署历史'"
        ;;
    *)
        echo "无效选项"
        ;;
esac
