#!/bin/bash

SERVER="49.235.161.106"
SSH_PORT="22"
SSH_USER="root"
PORT="10012"
PROJECT_NAME="blog"
DEPLOY_BASE="/opt/projects/${PROJECT_NAME}_${PORT}"

check_process() {
    echo "========================================="
    echo "进程状态"
    echo "========================================="
    
    ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "
        if [ -f ${DEPLOY_BASE}/backend/app.pid ]; then
            pid=\$(cat ${DEPLOY_BASE}/backend/app.pid)
            if ps -p \$pid > /dev/null 2>&1; then
                echo '✓ 后端服务运行中 (PID: '\$pid')'
                ps -p \$pid -o pid,ppid,%cpu,%mem,etime,args --no-headers
            else
                echo '✗ 后端服务未运行 (PID文件存在但进程不存在)'
            fi
        else
            echo '✗ 后端服务未运行 (无PID文件)'
        fi
        
        echo ''
        echo '端口 ${PORT} 监听状态:'
        netstat -tlnp 2>/dev/null | grep ':${PORT} ' || echo '端口 ${PORT} 未被监听'
    "
}

check_health() {
    echo ""
    echo "========================================="
    echo "健康检查"
    echo "========================================="
    
    ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "
        echo '--- 前端页面 ---'
        http_code=\$(curl -s -o /dev/null -w '%{http_code}' http://localhost:${PORT}/ 2>/dev/null)
        if [ \"\$http_code\" = \"200\" ]; then
            echo '✓ 前端页面正常 (HTTP '\$http_code')'
        else
            echo '✗ 前端页面异常 (HTTP '\$http_code')'
        fi
        
        echo ''
        echo '--- 后端接口 ---'
        http_code=\$(curl -s -o /dev/null -w '%{http_code}' http://localhost:${PORT}/api/todos 2>/dev/null)
        if [ \"\$http_code\" = \"200\" ] || [ \"\$http_code\" = \"404\" ]; then
            echo '✓ 后端接口正常 (HTTP '\$http_code')'
        else
            echo '✗ 后端接口异常 (HTTP '\$http_code')'
        fi
        
        echo ''
        echo '--- 外部访问 ---'
        http_code=\$(curl -s -o /dev/null -w '%{http_code}' http://${SERVER}:${PORT}/ 2>/dev/null)
        if [ \"\$http_code\" = \"200\" ]; then
            echo '✓ 外部访问正常 (HTTP '\$http_code')'
        else
            echo '✗ 外部访问异常 (HTTP '\$http_code')'
        fi
    "
}

check_files() {
    echo ""
    echo "========================================="
    echo "文件状态"
    echo "========================================="
    
    ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "
        echo '--- 后端文件 ---'
        if ls ${DEPLOY_BASE}/backend/*.jar >/dev/null 2>&1; then
            ls -lh ${DEPLOY_BASE}/backend/*.jar | grep -v '\.original'
        else
            echo '无JAR包'
        fi
        
        echo ''
        echo '--- 前端文件 ---'
        if [ -d ${DEPLOY_BASE}/frontend/dist ]; then
            file_count=\$(find ${DEPLOY_BASE}/frontend/dist -type f | wc -l)
            echo '✓ 前端dist目录存在 ('\$file_count' 个文件)'
        else
            echo '✗ 前端dist目录不存在'
        fi
        
        echo ''
        echo '--- 日志文件 ---'
        ls -lh ${DEPLOY_BASE}/logs/*.log 2>/dev/null || echo '无日志文件'
        
        echo ''
        echo '--- Nginx配置 ---'
        if [ -f ${DEPLOY_BASE}/nginx/app.conf ]; then
            echo '✓ Nginx配置文件存在'
        else
            echo '✗ Nginx配置文件不存在'
        fi
    "
}

check_deploy_info() {
    echo ""
    echo "========================================="
    echo "部署信息"
    echo "========================================="
    
    ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "
        if [ -f ${DEPLOY_BASE}/deploy_info.json ]; then
            cat ${DEPLOY_BASE}/deploy_info.json
        else
            echo '无部署信息文件'
        fi
    "
}

check_resources() {
    echo ""
    echo "========================================="
    echo "资源使用"
    echo "========================================="
    
    ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "
        echo '--- 磁盘使用 ---'
        df -h ${DEPLOY_BASE} 2>/dev/null || df -h /opt
        
        echo ''
        echo '--- 项目目录大小 ---'
        du -sh ${DEPLOY_BASE} 2>/dev/null || echo '目录不存在'
        
        echo ''
        echo '--- 备份目录大小 ---'
        du -sh /opt/backups/${PROJECT_NAME}_${PORT} 2>/dev/null || echo '备份目录不存在'
    "
}

main() {
    echo "========================================="
    echo "服务状态检查 ${PROJECT_NAME} 端口: ${PORT}"
    echo "========================================="
    
    check_process
    check_health
    check_files
    check_deploy_info
    check_resources
    
    echo ""
    echo "========================================="
    echo "检查完成"
    echo "========================================="
}

main "$@"
