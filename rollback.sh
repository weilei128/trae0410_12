#!/bin/bash

set -e

SERVER="49.235.161.106"
SSH_PORT="22"
SSH_USER="root"
PORT="10012"
PROJECT_NAME="blog"
DEPLOY_BASE="/opt/projects/${PROJECT_NAME}_${PORT}"
BACKUP_BASE="/opt/backups/${PROJECT_NAME}_${PORT}"
DEPLOY_LOG="/opt/deploy_logs/${PROJECT_NAME}_${PORT}.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$DEPLOY_LOG" 2>/dev/null || true
}

list_backups() {
    log "========================================="
    log "可用的备份列表:"
    log "========================================="
    
    ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "
        echo '--- JAR包备份 ---'
        ls -lht ${BACKUP_BASE}/*.jar.* 2>/dev/null || echo '无JAR包备份'
        echo ''
        echo '--- 前端备份 ---'
        ls -lht ${BACKUP_BASE}/dist.* 2>/dev/null || echo '无前端备份'
    "
}

get_latest_backup() {
    local backup_type=$1
    local latest
    
    case $backup_type in
        jar)
            latest=$(ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "ls -t ${BACKUP_BASE}/*.jar.* 2>/dev/null | head -1")
            ;;
        frontend)
            latest=$(ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "ls -td ${BACKUP_BASE}/dist.* 2>/dev/null | head -1")
            ;;
    esac
    
    echo "$latest"
}

stop_backend() {
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
                echo '后端服务已停止'
            else
                echo '后端服务未运行'
            fi
        else
            echo 'PID文件不存在'
        fi
    "
}

rollback_jar() {
    local backup_file=$1
    
    if [ -z "$backup_file" ]; then
        backup_file=$(get_latest_backup "jar")
    fi
    
    if [ -z "$backup_file" ]; then
        log "错误: 未找到JAR包备份"
        exit 1
    fi
    
    log "回滚JAR包: $backup_file"
    
    JAR_NAME=$(ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "basename ${backup_file} | sed 's/\.[0-9_]\+$//'")
    
    ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "
        cp ${backup_file} ${DEPLOY_BASE}/backend/${JAR_NAME}
        echo 'JAR包回滚完成'
    "
}

rollback_frontend() {
    local backup_dir=$1
    
    if [ -z "$backup_dir" ]; then
        backup_dir=$(get_latest_backup "frontend")
    fi
    
    if [ -z "$backup_dir" ]; then
        log "错误: 未找到前端备份"
        exit 1
    fi
    
    log "回滚前端: $backup_dir"
    
    ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "
        rm -rf ${DEPLOY_BASE}/frontend/dist
        cp -r ${backup_dir} ${DEPLOY_BASE}/frontend/dist
        echo '前端回滚完成'
    "
}

start_backend() {
    log "启动后端服务..."
    
    JAR_NAME=$(ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "ls ${DEPLOY_BASE}/backend/*.jar | grep -v '\.original' | head -1 | xargs basename")
    
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
            echo '后端服务启动失败'
            exit 1
        fi
    "
}

reload_nginx() {
    log "重载Nginx配置..."
    ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "
        nginx -t && nginx -s reload 2>/dev/null || nginx
        echo 'Nginx重载完成'
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

show_usage() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  list              列出所有可用备份"
    echo "  jar [备份文件]    回滚JAR包到指定备份(默认最新)"
    echo "  frontend [目录]   回滚前端到指定备份(默认最新)"
    echo "  all               回滚JAR包和前端到最新备份"
    echo ""
    echo "示例:"
    echo "  $0 list"
    echo "  $0 jar"
    echo "  $0 frontend"
    echo "  $0 all"
}

main() {
    log "========================================="
    log "开始回滚 ${PROJECT_NAME} 端口: ${PORT}"
    log "========================================="
    
    case "${1:-}" in
        list)
            list_backups
            ;;
        jar)
            stop_backend
            rollback_jar "${2:-}"
            start_backend
            health_check
            ;;
        frontend)
            rollback_frontend "${2:-}"
            reload_nginx
            health_check
            ;;
        all)
            stop_backend
            rollback_jar
            rollback_frontend
            start_backend
            reload_nginx
            health_check
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
    
    log "========================================="
    log "回滚操作完成"
    log "========================================="
}

main "$@"
