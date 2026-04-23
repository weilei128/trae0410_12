#!/bin/bash

set -e

SERVER="49.235.161.106"
SSH_PORT="22"
SSH_USER="root"
PORT="10012"
PROJECT_NAME="blog"
DEPLOY_BASE="/opt/projects/${PROJECT_NAME}_${PORT}"
BACKUP_BASE="/opt/backups/${PROJECT_NAME}_${PORT}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEPLOY_LOG="/opt/deploy_logs/${PROJECT_NAME}_${PORT}.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    mkdir -p "$(dirname "$DEPLOY_LOG")" 2>/dev/null || true
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$DEPLOY_LOG" 2>/dev/null || true
}

log "========================================="
log "开始部署 ${PROJECT_NAME} 端口: ${PORT}"
log "========================================="

check_ssh_key() {
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 -p "$SSH_PORT" "$SSH_USER@$SERVER" "echo ok" 2>/dev/null; then
        log "错误: SSH密钥认证失败，请确保已配置SSH密钥"
        exit 1
    fi
    log "SSH密钥认证成功"
}

kill_port_process() {
    log "检查并清理端口 ${PORT} 占用进程..."
    
    ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "
        set -e
        pids=\$(netstat -tlnp 2>/dev/null | grep ':${PORT} ' | awk '{print \$7}' | cut -d'/' -f1 | grep -v '-' | sort -u)
        
        if [ -z \"\$pids\" ]; then
            echo '端口 ${PORT} 未被占用'
            exit 0
        fi
        
        for pid in \$pids; do
            if [ -n \"\$pid\" ] && [ \"\$pid\" != \"-\" ]; then
                cmd=\$(ps -p \$pid -o args= 2>/dev/null || echo '')
                if echo \"\$cmd\" | grep -qE '(java|node|nginx)'; then
                    echo \"找到占用进程 PID: \$pid, 命令: \$cmd\"
                    kill -15 \$pid 2>/dev/null || true
                    sleep 2
                    if ps -p \$pid > /dev/null 2>&1; then
                        kill -9 \$pid 2>/dev/null || true
                    fi
                    echo \"已终止进程 \$pid\"
                else
                    echo \"跳过非项目进程 PID: \$pid\"
                fi
            fi
        done
        echo '端口 ${PORT} 清理完成'
    "
}

build_backend() {
    log "开始构建后端..."
    cd backend
    if [ -f "mvnw" ]; then
        chmod +x mvnw
        ./mvnw clean package -DskipTests
    else
        mvn clean package -DskipTests
    fi
    cd ..
    log "后端构建完成"
}

build_frontend() {
    log "开始构建前端..."
    cd frontend
    if [ -f "package-lock.json" ]; then
        npm ci
    else
        npm install
    fi
    npm run build
    cd ..
    log "前端构建完成"
}

prepare_server_dirs() {
    log "准备服务器目录结构..."
    ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "
        mkdir -p ${DEPLOY_BASE}/{backend,frontend,logs,nginx}
        mkdir -p ${BACKUP_BASE}
        mkdir -p /opt/deploy_logs
        mkdir -p /opt/nginx_confs
    "
    log "目录结构准备完成"
}

upload_backend() {
    log "上传后端文件..."
    
    JAR_FILE=$(ls backend/target/*.jar 2>/dev/null | grep -v '\.original' | head -1)
    if [ -z "$JAR_FILE" ]; then
        log "错误: 未找到后端jar包"
        exit 1
    fi
    
    JAR_NAME=$(basename "$JAR_FILE")
    
    ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "
        if [ -f ${DEPLOY_BASE}/backend/${JAR_NAME} ]; then
            cp ${DEPLOY_BASE}/backend/${JAR_NAME} ${BACKUP_BASE}/${JAR_NAME}.${TIMESTAMP}
            echo '已备份旧版本jar包'
        fi
    "
    
    scp -P "$SSH_PORT" "$JAR_FILE" "$SSH_USER@$SERVER:${DEPLOY_BASE}/backend/${JAR_NAME}"
    log "后端文件上传完成: ${JAR_NAME}"
}

upload_frontend() {
    log "上传前端文件..."
    
    if [ ! -d "frontend/dist" ]; then
        log "错误: 前端dist目录不存在"
        exit 1
    fi
    
    ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "
        if [ -d ${DEPLOY_BASE}/frontend/dist ]; then
            mv ${DEPLOY_BASE}/frontend/dist ${BACKUP_BASE}/dist.${TIMESTAMP}
            echo '已备份旧版本前端文件'
        fi
    "
    
    scp -P "$SSH_PORT" -r frontend/dist "$SSH_USER@$SERVER:${DEPLOY_BASE}/frontend/"
    log "前端文件上传完成"
}

create_nginx_config() {
    log "创建Nginx配置..."
    
    ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "cat > ${DEPLOY_BASE}/nginx/app.conf << 'NGINX_EOF'
server {
    listen ${PORT};
    server_name localhost;
    
    access_log ${DEPLOY_BASE}/logs/nginx_access.log;
    error_log ${DEPLOY_BASE}/logs/nginx_error.log;
    
    location / {
        root ${DEPLOY_BASE}/frontend/dist;
        index index.html;
        try_files \$uri \$uri/ /index.html;
    }
    
    location /api {
        proxy_pass http://127.0.0.1:${PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    location /health {
        return 200 'OK';
        add_header Content-Type text/plain;
    }
}
NGINX_EOF"

    ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "
        if [ -f /etc/nginx/nginx.conf ]; then
            if ! grep -q \"include ${DEPLOY_BASE}/nginx/app.conf\" /etc/nginx/nginx.conf; then
                sed -i '/http {/a\\    include ${DEPLOY_BASE}/nginx/app.conf;' /etc/nginx/nginx.conf 2>/dev/null || true
            fi
            nginx -t && nginx -s reload 2>/dev/null || nginx
            echo 'Nginx配置完成'
        else
            echo 'Nginx未安装，跳过配置'
        fi
    "
    log "Nginx配置创建完成"
}

start_backend() {
    log "启动后端服务..."
    
    JAR_NAME=$(ls backend/target/*.jar 2>/dev/null | grep -v '\.original' | xargs basename)
    
    ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "
        cd ${DEPLOY_BASE}/backend
        
        nohup java -Xms128m -Xmx256m \\
            -jar ${JAR_NAME} \\
            --server.port=${PORT} \\
            > ${DEPLOY_BASE}/logs/app.log 2>&1 &
        
        echo \$! > ${DEPLOY_BASE}/backend/app.pid
        sleep 3
        
        if ps -p \$(cat ${DEPLOY_BASE}/backend/app.pid 2>/dev/null) > /dev/null 2>&1; then
            echo '后端服务启动成功, PID: '\$(cat ${DEPLOY_BASE}/backend/app.pid)
        else
            echo '后端服务启动失败，查看日志:'
            tail -50 ${DEPLOY_BASE}/logs/app.log
            exit 1
        fi
    "
    log "后端服务启动完成"
}

health_check() {
    log "执行健康检查..."
    
    local frontend_ok=false
    local backend_ok=false
    
    sleep 5
    
    log "检查前端页面..."
    if ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "curl -s -o /dev/null -w '%{http_code}' http://localhost:${PORT}/" | grep -q "200"; then
        log "✓ 前端页面访问正常"
        frontend_ok=true
    else
        log "✗ 前端页面访问异常"
    fi
    
    log "检查后端接口..."
    if ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "curl -s -o /dev/null -w '%{http_code}' http://localhost:${PORT}/api/todos" | grep -qE "200|404"; then
        log "✓ 后端接口访问正常"
        backend_ok=true
    else
        log "✗ 后端接口访问异常"
    fi
    
    if $frontend_ok && $backend_ok; then
        log "========================================="
        log "健康检查全部通过"
        log "========================================="
        return 0
    else
        log "========================================="
        log "健康检查存在失败项"
        log "========================================="
        return 1
    fi
}

record_deployment() {
    log "记录部署信息..."
    
    ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "cat > ${DEPLOY_BASE}/deploy_info.json << 'EOF'
{
    \"project\": \"${PROJECT_NAME}\",
    \"port\": ${PORT},
    \"deploy_time\": \"$(date '+%Y-%m-%d %H:%M:%S')\",
    \"timestamp\": \"${TIMESTAMP}\",
    \"server\": \"${SERVER}\",
    \"status\": \"success\"
}
EOF
cat ${DEPLOY_BASE}/deploy_info.json"
    log "部署信息已记录"
}

main() {
    log "步骤 1/10: 检查SSH连接"
    check_ssh_key
    
    log "步骤 2/10: 清理端口占用"
    kill_port_process
    
    log "步骤 3/10: 构建后端"
    build_backend
    
    log "步骤 4/10: 构建前端"
    build_frontend
    
    log "步骤 5/10: 准备服务器目录"
    prepare_server_dirs
    
    log "步骤 6/10: 上传后端文件"
    upload_backend
    
    log "步骤 7/10: 上传前端文件"
    upload_frontend
    
    log "步骤 8/10: 配置Nginx"
    create_nginx_config
    
    log "步骤 9/10: 启动后端服务"
    start_backend
    
    log "步骤 10/10: 健康检查"
    if health_check; then
        record_deployment
        log "========================================="
        log "部署成功完成！"
        log "访问地址: http://${SERVER}:${PORT}"
        log "========================================="
    else
        log "部署完成但健康检查未通过，请检查日志"
        exit 1
    fi
}

main "$@"
