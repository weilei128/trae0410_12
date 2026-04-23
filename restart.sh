#!/bin/bash

SERVER="49.235.161.106"
SSH_PORT="22"
SSH_USER="root"
PORT="10012"
PROJECT_NAME="blog"
DEPLOY_BASE="/opt/projects/${PROJECT_NAME}_${PORT}"
DEPLOY_LOG="/opt/deploy_logs/${PROJECT_NAME}_${PORT}.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$DEPLOY_LOG" 2>/dev/null || true
}

stop_service() {
    log "停止后端服务..."
    
    ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "
        if [ -f ${DEPLOY_BASE}/backend/app.pid ]; then
            pid=\$(cat ${DEPLOY_BASE}/backend/app.pid)
            if ps -p \$pid > /dev/null 2>&1; then
                kill -15 \$pid
                sleep 3
                if ps -p \$pid > /dev/null 2>&1; then
                    kill -9 \$pid
                fi
                echo '后端服务已停止 (PID: '\$pid')'
            else
                echo '后端服务未运行'
            fi
            rm -f ${DEPLOY_BASE}/backend/app.pid
        else
            echo 'PID文件不存在，尝试通过端口查找进程'
            pid=\$(netstat -tlnp 2>/dev/null | grep ':${PORT} ' | awk '{print \$7}' | cut -d'/' -f1 | head -1)
            if [ -n \"\$pid\" ] && [ \"\$pid\" != \"-\" ]; then
                kill -15 \$pid
                sleep 2
                echo '已终止端口 ${PORT} 上的进程 (PID: '\$pid')'
            else
                echo '未找到运行中的服务'
            fi
        fi
    "
}

start_service() {
    log "启动后端服务..."
    
    JAR_NAME=$(ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "ls ${DEPLOY_BASE}/backend/*.jar 2>/dev/null | grep -v '\.original' | head -1 | xargs basename 2>/dev/null || echo ''")
    
    if [ -z "$JAR_NAME" ]; then
        log "错误: 未找到JAR包"
        exit 1
    fi
    
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
            tail -20 ${DEPLOY_BASE}/logs/app.log
            exit 1
        fi
    "
}

health_check() {
    log "执行健康检查..."
    sleep 3
    
    local frontend_ok=false
    local backend_ok=false
    
    if ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "curl -s -o /dev/null -w '%{http_code}' http://localhost:${PORT}/" | grep -q "200"; then
        log "✓ 前端页面访问正常"
        frontend_ok=true
    else
        log "✗ 前端页面访问异常"
    fi
    
    if ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "curl -s -o /dev/null -w '%{http_code}' http://localhost:${PORT}/api/todos" | grep -qE "200|404"; then
        log "✓ 后端接口访问正常"
        backend_ok=true
    else
        log "✗ 后端接口访问异常"
    fi
    
    if $frontend_ok && $backend_ok; then
        log "健康检查通过"
        return 0
    else
        log "健康检查失败"
        return 1
    fi
}

main() {
    log "========================================="
    log "重启服务 ${PROJECT_NAME} 端口: ${PORT}"
    log "========================================="
    
    stop_service
    sleep 2
    start_service
    health_check
    
    log "========================================="
    log "重启完成"
    log "========================================="
}

main "$@"
