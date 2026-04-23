#!/bin/bash

set -e

PROJECT_PORT=10011
BACKEND_PORT=100110
SERVER_IP="49.235.161.106"
SERVER_USER="root"
SSH_PORT=22
BASE_DIR="/opt/blog-instance-${PROJECT_PORT}"
JAR_NAME="todo-app.jar"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

echo "======================================"
echo "开始部署后端服务 - 实例端口: ${PROJECT_PORT}"
echo "======================================"

echo "[1/5] 后端本地打包..."
cd "${PROJECT_ROOT}/backend"

if [ -f "pom.xml" ]; then
    echo "使用Maven打包..."
    if command -v mvn &> /dev/null; then
        mvn clean package -DskipTests
    else
        echo "Maven未在本地找到，使用已编译的jar包..."
    fi
else
    echo "未找到pom.xml，跳过本地打包"
fi

JAR_SOURCE=$(find "${PROJECT_ROOT}/backend/target" -name "*.jar" -type f | grep -v "original" | head -1)
if [ -z "${JAR_SOURCE}" ]; then
    echo "错误: 未找到jar包"
    exit 1
fi
echo "找到jar包: ${JAR_SOURCE}"

BACKUP_TIME=$(date "+%Y%m%d_%H%M%S")
echo "[2/5] 备份当前版本..."
ssh -p ${SSH_PORT} ${SERVER_USER}@${SERVER_IP} "bash -s" << EOF
if [ -f "${BASE_DIR}/backend/${JAR_NAME}" ]; then
    cp "${BASE_DIR}/backend/${JAR_NAME}" "${BASE_DIR}/backup/${JAR_NAME}.${BACKUP_TIME}"
    echo "已备份到: ${BASE_DIR}/backup/${JAR_NAME}.${BACKUP_TIME}"
fi
EOF

echo "[3/5] 上传jar包到服务器..."
scp -P ${SSH_PORT} "${JAR_SOURCE}" ${SERVER_USER}@${SERVER_IP}:${BASE_DIR}/backend/${JAR_NAME}

echo "[4/5] 启动后端服务..."
ssh -p ${SSH_PORT} ${SERVER_USER}@${SERVER_IP} "bash -s" << EOF
if ! command -v java &> /dev/null; then
    echo "Java未安装，正在安装OpenJDK 11..."
    apt-get update && apt-get install -y openjdk-11-jre || yum install -y java-11-openjdk
fi

cat > ${BASE_DIR}/script/stop-backend.sh << 'STOPSCRIPT'
#!/bin/bash
PID_FILE="${BASE_DIR}/backend/app.pid"
if [ -f "\${PID_FILE}" ]; then
    PID=\$(cat "\${PID_FILE}")
    if kill -0 \${PID} 2>/dev/null; then
        echo "正在停止后端服务 PID: \${PID}"
        kill -15 \${PID}
        for i in 1 2 3 4 5; do
            if ! kill -0 \${PID} 2>/dev/null; then
                echo "服务已停止"
                break
            fi
            sleep 1
        done
        if kill -0 \${PID} 2>/dev/null; then
            echo "强制终止进程"
            kill -9 \${PID}
        fi
    fi
    rm -f "\${PID_FILE}"
else
    echo "未找到运行中的服务"
fi
STOPSCRIPT

chmod +x ${BASE_DIR}/script/stop-backend.sh

echo "停止旧的后端服务..."
${BASE_DIR}/script/stop-backend.sh

echo "启动新的后端服务..."
cd ${BASE_DIR}/backend
nohup java -jar -Dserver.port=${BACKEND_PORT} ${JAR_NAME} > ${BASE_DIR}/logs/backend.log 2>&1 &
echo \$! > ${BASE_DIR}/backend/app.pid

echo "等待服务启动..."
sleep 10
EOF

echo "[5/5] 查看后端启动日志..."
ssh -p ${SSH_PORT} ${SERVER_USER}@${SERVER_IP} "tail -30 ${BASE_DIR}/logs/backend.log"

echo "======================================"
echo "后端服务部署完成!"
echo "后端端口: ${BACKEND_PORT}"
echo "启动脚本: ${BASE_DIR}/script/stop-backend.sh"
echo "日志文件: ${BASE_DIR}/logs/backend.log"
echo "======================================"
