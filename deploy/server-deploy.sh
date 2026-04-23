#!/bin/bash
set -e

PROJECT_PORT=10011
BACKEND_PORT=100110
BASE_DIR=/opt/blog-instance-${PROJECT_PORT}

echo "======================================"
echo "服务器端部署 - 端口 ${PROJECT_PORT}"
echo "======================================"

echo "[1] 安装依赖..."
apt-get update -qq && apt-get install -y -qq openjdk-11-jre-headless nginx net-tools lsof

echo "[2] 创建目录结构..."
mkdir -p ${BASE_DIR}/backend ${BASE_DIR}/frontend/dist ${BASE_DIR}/logs ${BASE_DIR}/backup ${BASE_DIR}/script

echo "[3] 清理端口..."
for PORT in ${PROJECT_PORT} ${BACKEND_PORT}; do
    PIDS=$(lsof -ti:${PORT} 2>/dev/null || echo "")
    if [ -n "${PIDS}" ]; then
        echo "Kill port ${PORT}: ${PIDS}"
        kill -9 ${PIDS} 2>/dev/null || true
    fi
done

echo "[4] 部署后端..."
mv /tmp/todo-app-1.0.0.jar ${BASE_DIR}/backend/todo-app.jar
cd ${BASE_DIR}/backend
nohup java -jar -Dserver.port=${BACKEND_PORT} todo-app.jar > ${BASE_DIR}/logs/backend.log 2>&1 &
echo $! > ${BASE_DIR}/backend/app.pid
echo "Backend PID: $!"

echo "[5] 配置Nginx..."
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
    }
}
NGINXCONF

nginx -t && systemctl restart nginx

sleep 8

echo "[6] 健康检查..."
echo "后端接口测试:"
curl -s http://localhost:${BACKEND_PORT}/api/todo
echo ""
echo "Nginx端口测试:"
curl -s -o /dev/null -w "HTTP %{http_code}" http://localhost:${PROJECT_PORT}/
echo ""

echo "======================================"
echo "部署完成!"
echo "前端: http://49.235.161.106:${PROJECT_PORT}"
echo "后端: http://49.235.161.106:${PROJECT_PORT}/api/todo"
echo "目录: ${BASE_DIR}"
echo "======================================"
netstat -tlnp | grep -E "10011|nginx"
