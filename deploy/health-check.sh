#!/bin/bash

set +e

PROJECT_PORT=10011
BACKEND_PORT=100110
SERVER_IP="49.235.161.106"
SERVER_USER="root"
SSH_PORT=22
BASE_DIR="/opt/blog-instance-${PROJECT_PORT}"

CHECK_TIME=$(date "+%Y-%m-%d %H:%M:%S")
echo "======================================"
echo "健康检查 - ${CHECK_TIME}"
echo "======================================"

RESULT_FILE="${BASE_DIR}/health-check-result.log"

echo "开始健康检查..."

FRONTEND_STATUS="FAIL"
echo "[1/3] 检查前端页面..."
for i in 1 2 3; do
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://${SERVER_IP}:${PROJECT_PORT}/" --connect-timeout 5 --max-time 10)
    if [ "${HTTP_STATUS}" = "200" ]; then
        FRONTEND_STATUS="OK"
        echo "✅ 前端页面访问正常 (HTTP ${HTTP_STATUS})"
        break
    fi
    echo "重试 ${i}/3: HTTP状态 ${HTTP_STATUS}"
    sleep 3
done

if [ "${FRONTEND_STATUS}" = "FAIL" ]; then
    echo "❌ 前端页面访问失败"
fi

BACKEND_STATUS="FAIL"
echo "[2/3] 检查后端接口..."
for i in 1 2 3; do
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://${SERVER_IP}:${PROJECT_PORT}/api/todo" --connect-timeout 5 --max-time 10)
    if [ "${HTTP_STATUS}" = "200" ] || [ "${HTTP_STATUS}" = "404" ]; then
        BACKEND_STATUS="OK"
        echo "✅ 后端接口响应正常 (HTTP ${HTTP_STATUS})"
        break
    fi
    echo "重试 ${i}/3: HTTP状态 ${HTTP_STATUS}"
    sleep 3
done

if [ "${BACKEND_STATUS}" = "FAIL" ]; then
    echo "❌ 后端接口访问失败"
fi

echo "[3/3] 服务器端进程和端口检查..."
ssh -p ${SSH_PORT} ${SERVER_USER}@${SERVER_IP} "bash -s" << EOF
echo ""
echo "--- 服务器端口检查 ---"
echo "Nginx端口 ${PROJECT_PORT}:"
netstat -tlnp | grep ":${PROJECT_PORT} " || echo "端口 ${PROJECT_PORT} 未监听"
echo ""
echo "后端端口 ${BACKEND_PORT}:"
netstat -tlnp | grep ":${BACKEND_PORT} " || echo "端口 ${BACKEND_PORT} 未监听"

echo ""
echo "--- Java进程检查 ---"
PID_FILE="${BASE_DIR}/backend/app.pid"
if [ -f "\${PID_FILE}" ]; then
    PID=\$(cat "\${PID_FILE}")
    if ps -p \${PID} > /dev/null 2>&1; then
        echo "✅ 后端服务运行中，PID: \${PID}"
        ps -p \${PID} -o pid,ppid,cmd,%mem,%cpu --no-headers
    else
        echo "❌ 后端服务进程不存在"
    fi
else
    echo "⚠️  未找到PID文件"
fi

echo ""
echo "--- 磁盘空间检查 ---"
df -h ${BASE_DIR} | tail -1
EOF

echo ""
echo "======================================"
echo "健康检查总结:"
echo "======================================"
echo "检查时间: ${CHECK_TIME}"
echo "前端页面: ${FRONTEND_STATUS}"
echo "后端接口: ${BACKEND_STATUS}"
echo "服务器: ${SERVER_IP}:${PROJECT_PORT}"
echo "======================================"

ssh -p ${SSH_PORT} ${SERVER_USER}@${SERVER_IP} "cat > ${RESULT_FILE} << EOF
======================================
健康检查报告
检查时间: ${CHECK_TIME}
前端状态: ${FRONTEND_STATUS}
后端状态: ${BACKEND_STATUS}
前端地址: http://${SERVER_IP}:${PROJECT_PORT}
后端地址: http://${SERVER_IP}:${PROJECT_PORT}/api/todo
======================================
EOF"

if [ "${FRONTEND_STATUS}" = "OK" ] && [ "${BACKEND_STATUS}" = "OK" ]; then
    echo "✅ 健康检查全部通过!"
    exit 0
else
    echo "⚠️  部分检查未通过，请查看日志详情"
    exit 1
fi
