#!/bin/bash

SERVER="49.235.161.106"
SSH_PORT="22"
SSH_USER="root"
PORT="10012"
PROJECT_NAME="blog"
DEPLOY_BASE="/opt/projects/${PROJECT_NAME}_${PORT}"

show_usage() {
    echo "用法: $0 [选项] [行数]"
    echo ""
    echo "选项:"
    echo "  app      查看后端应用日志(默认)"
    echo "  nginx    查看Nginx访问日志"
    echo "  error    查看Nginx错误日志"
    echo "  deploy   查看部署日志"
    echo "  all      查看所有日志概览"
    echo "  follow   实时跟踪后端日志"
    echo ""
    echo "行数: 默认50行"
    echo ""
    echo "示例:"
    echo "  $0 app 100      查看后端日志最近100行"
    echo "  $0 nginx        查看Nginx访问日志"
    echo "  $0 follow       实时跟踪后端日志"
}

view_log() {
    local log_type=$1
    local lines=${2:-50}
    
    case $log_type in
        app)
            echo "========================================="
            echo "后端应用日志 (最近 ${lines} 行)"
            echo "========================================="
            ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "tail -n ${lines} ${DEPLOY_BASE}/logs/app.log 2>/dev/null || echo '日志文件不存在'"
            ;;
        nginx)
            echo "========================================="
            echo "Nginx访问日志 (最近 ${lines} 行)"
            echo "========================================="
            ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "tail -n ${lines} ${DEPLOY_BASE}/logs/nginx_access.log 2>/dev/null || echo '日志文件不存在'"
            ;;
        error)
            echo "========================================="
            echo "Nginx错误日志 (最近 ${lines} 行)"
            echo "========================================="
            ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "tail -n ${lines} ${DEPLOY_BASE}/logs/nginx_error.log 2>/dev/null || echo '日志文件不存在'"
            ;;
        deploy)
            echo "========================================="
            echo "部署日志 (最近 ${lines} 行)"
            echo "========================================="
            ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "tail -n ${lines} /opt/deploy_logs/${PROJECT_NAME}_${PORT}.log 2>/dev/null || echo '日志文件不存在'"
            ;;
        all)
            echo "========================================="
            echo "所有日志概览"
            echo "========================================="
            echo ""
            echo "--- 后端应用日志 ---"
            ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "tail -n 10 ${DEPLOY_BASE}/logs/app.log 2>/dev/null || echo '无'"
            echo ""
            echo "--- Nginx访问日志 ---"
            ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "tail -n 5 ${DEPLOY_BASE}/logs/nginx_access.log 2>/dev/null || echo '无'"
            echo ""
            echo "--- Nginx错误日志 ---"
            ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "tail -n 5 ${DEPLOY_BASE}/logs/nginx_error.log 2>/dev/null || echo '无'"
            echo ""
            echo "--- 部署日志 ---"
            ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "tail -n 5 /opt/deploy_logs/${PROJECT_NAME}_${PORT}.log 2>/dev/null || echo '无'"
            ;;
        follow)
            echo "========================================="
            echo "实时跟踪后端日志 (Ctrl+C 退出)"
            echo "========================================="
            ssh -p "$SSH_PORT" "$SSH_USER@$SERVER" "tail -f ${DEPLOY_BASE}/logs/app.log 2>/dev/null || echo '日志文件不存在'"
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
}

main() {
    case "${1:-}" in
        -h|--help|help)
            show_usage
            ;;
        app|nginx|error|deploy|all|follow)
            view_log "$1" "${2:-50}"
            ;;
        ''|*[0-9]*)
            view_log "app" "${1:-50}"
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
