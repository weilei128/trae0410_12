#!/bin/bash
# ============================================
# 主部署脚本 - 端口10013实例专用
# 功能：整合前后端部署、健康检查、回滚、一键重启
# ============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

# 部署结果记录文件
DEPLOY_RESULT_FILE="${BASE_DIR}/.deploy_result"

# 显示部署信息
show_deploy_info() {
    echo ""
    echo "=========================================="
    echo "  博客项目部署脚本 - 端口 ${APP_PORT} 实例"
    echo "=========================================="
    echo ""
    echo "服务器: ${SERVER_HOST}"
    echo "端口: ${APP_PORT}"
    echo "部署目录: ${BASE_DIR}"
    echo ""
    echo "=========================================="
}

# 记录部署结果
record_deploy_result() {
    local status=$1
    local message=$2
    local deploy_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    ssh -p ${SSH_PORT} -i "${SSH_KEY}" ${SERVER_USER}@${SERVER_HOST} << EOF
        mkdir -p ${BASE_DIR}
        cat > ${DEPLOY_RESULT_FILE} << RESULT
{
    "deploy_time": "${deploy_time}",
    "port": "${APP_PORT}",
    "status": "${status}",
    "message": "${message}",
    "frontend_url": "http://${SERVER_HOST}:${APP_PORT}",
    "backend_url": "http://${SERVER_HOST}:${APP_PORT}/api/todos"
}
RESULT
EOF
    
    log_info "部署结果已记录到: ${DEPLOY_RESULT_FILE}"
}

# 完整部署流程
full_deploy() {
    show_deploy_info
    
    local deploy_start_time=$(date +%s)
    log_info "========== 开始完整部署 =========="
    
    # 步骤1: 部署后端
    log_info "---------- 步骤1: 部署后端 ----------"
    if ! bash "${SCRIPT_DIR}/backend.sh" deploy; then
        log_error "后端部署失败"
        record_deploy_result "FAILED" "后端部署失败"
        exit 1
    fi
    
    # 步骤2: 部署前端
    log_info "---------- 步骤2: 部署前端 ----------"
    if ! bash "${SCRIPT_DIR}/frontend.sh" deploy; then
        log_error "前端部署失败"
        record_deploy_result "FAILED" "前端部署失败"
        exit 1
    fi
    
    # 步骤3: 双维度健康检查
    log_info "---------- 步骤3: 健康检查 ----------"
    local health_check_passed=true
    
    # 后端健康检查
    log_info "检查后端API..."
    if ! bash "${SCRIPT_DIR}/backend.sh" health; then
        health_check_passed=false
        log_error "后端健康检查失败"
    fi
    
    # 前端健康检查
    log_info "检查前端页面..."
    if ! bash "${SCRIPT_DIR}/frontend.sh" health; then
        health_check_passed=false
        log_error "前端健康检查失败"
    fi
    
    # 计算部署耗时
    local deploy_end_time=$(date +%s)
    local deploy_duration=$((deploy_end_time - deploy_start_time))
    
    # 输出部署结果
    echo ""
    echo "=========================================="
    if [ "$health_check_passed" = true ]; then
        log_success "========== 部署成功 =========="
        record_deploy_result "SUCCESS" "部署成功，所有健康检查通过"
        
        echo ""
        echo "访问地址:"
        echo "  前端页面: http://${SERVER_HOST}:${APP_PORT}"
        echo "  后端API:  http://${SERVER_HOST}:${APP_PORT}/api/todos"
        echo ""
        echo "部署耗时: ${deploy_duration} 秒"
        echo "部署时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "=========================================="
        return 0
    else
        log_error "========== 部署失败 =========="
        record_deploy_result "FAILED" "健康检查未通过"
        echo ""
        echo "部分服务未通过健康检查，请查看日志:"
        echo "  后端日志: bash deploy/backend.sh view-logs 100"
        echo ""
        echo "可执行回滚: bash deploy/deploy.sh rollback"
        echo "=========================================="
        return 1
    fi
}

# 仅部署后端
deploy_backend_only() {
    log_info "========== 仅部署后端 =========="
    
    if bash "${SCRIPT_DIR}/backend.sh" deploy; then
        log_success "后端部署完成"
        record_deploy_result "SUCCESS" "仅后端部署成功"
    else
        log_error "后端部署失败"
        record_deploy_result "FAILED" "后端部署失败"
        exit 1
    fi
}

# 仅部署前端
deploy_frontend_only() {
    log_info "========== 仅部署前端 =========="
    
    if bash "${SCRIPT_DIR}/frontend.sh" deploy; then
        log_success "前端部署完成"
        record_deploy_result "SUCCESS" "仅前端部署成功"
    else
        log_error "前端部署失败"
        record_deploy_result "FAILED" "前端部署失败"
        exit 1
    fi
}

# 一键重启
restart_all() {
    log_info "========== 一键重启 =========="
    
    # 停止后端
    bash "${SCRIPT_DIR}/backend.sh" stop
    
    # 等待片刻
    sleep 2
    
    # 启动后端
    bash "${SCRIPT_DIR}/backend.sh" start
    
    # 等待服务启动
    sleep 5
    
    # 重载Nginx
    bash "${SCRIPT_DIR}/frontend.sh" nginx-config
    
    # 健康检查
    log_info "执行健康检查..."
    bash "${SCRIPT_DIR}/backend.sh" health
    bash "${SCRIPT_DIR}/frontend.sh" health
    
    log_success "重启完成"
}

# 回滚操作
rollback() {
    log_info "========== 执行回滚 =========="
    
    echo "此操作将回滚到上一个成功部署的版本"
    read -p "确认执行回滚? (y/N): " confirm
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        bash "${SCRIPT_DIR}/backend.sh" rollback
        
        # 重新部署前端（保持配置一致）
        bash "${SCRIPT_DIR}/frontend.sh" nginx-config
        
        # 健康检查
        sleep 5
        bash "${SCRIPT_DIR}/backend.sh" health
        bash "${SCRIPT_DIR}/frontend.sh" health
        
        record_deploy_result "ROLLED_BACK" "已回滚到上一个版本"
        log_success "回滚完成"
    else
        log_info "回滚已取消"
    fi
}

# 查看部署结果
show_deploy_result() {
    log_info "查看部署结果..."
    
    ssh -p ${SSH_PORT} -i "${SSH_KEY}" ${SERVER_USER}@${SERVER_HOST} \
        "cat ${DEPLOY_RESULT_FILE} 2>/dev/null || echo '暂无部署记录'"
}

# 查看服务状态
show_status() {
    log_info "========== 服务状态 =========="
    
    echo ""
    echo "后端状态:"
    bash "${SCRIPT_DIR}/backend.sh" status
    
    echo ""
    echo "端口监听情况:"
    ssh -p ${SSH_PORT} -i "${SSH_KEY}" ${SERVER_USER}@${SERVER_HOST} \
        "netstat -tlnp 2>/dev/null | grep ':${APP_PORT}' || ss -tlnp | grep ':${APP_PORT}' || echo '端口未监听'"
    
    echo ""
    echo "Nginx配置:"
    ssh -p ${SSH_PORT} -i "${SSH_KEY}" ${SERVER_USER}@${SERVER_HOST} \
        "ls -la ${NGINX_CONF_FILE} 2>/dev/null && echo 'Nginx配置存在' || echo 'Nginx配置不存在'"
    
    echo ""
    echo "目录结构:"
    ssh -p ${SSH_PORT} -i "${SSH_KEY}" ${SERVER_USER}@${SERVER_HOST} \
        "ls -la ${BASE_DIR}/"
}

# 查看日志
show_logs() {
    local service=$1
    local lines=${2:-50}
    
    case $service in
        backend)
            bash "${SCRIPT_DIR}/backend.sh" view-logs $lines
            ;;
        frontend)
            ssh -p ${SSH_PORT} -i "${SSH_KEY}" ${SERVER_USER}@${SERVER_HOST} \
                "tail -n ${lines} ${LOGS_DIR}/nginx_error.log 2>/dev/null || echo '暂无前端错误日志'"
            ;;
        *)
            echo "用法: $0 logs {backend|frontend} [行数]"
            exit 1
            ;;
    esac
}

# 实时监控日志
follow_logs() {
    local service=$1
    
    case $service in
        backend)
            bash "${SCRIPT_DIR}/backend.sh" logs
            ;;
        *)
            echo "用法: $0 follow-logs {backend}"
            exit 1
            ;;
    esac
}

# 清理部署环境
cleanup() {
    log_info "========== 清理部署环境 =========="
    
    echo "此操作将停止服务并清理所有部署文件"
    read -p "确认执行清理? (y/N): " confirm
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        # 停止服务
        bash "${SCRIPT_DIR}/backend.sh" stop
        bash "${SCRIPT_DIR}/frontend.sh" stop
        
        # 清理服务器目录
        ssh -p ${SSH_PORT} -i "${SSH_KEY}" ${SERVER_USER}@${SERVER_HOST} \
            "rm -rf ${BASE_DIR} && echo '服务器目录已清理'"
        
        log_success "清理完成"
    else
        log_info "清理已取消"
    fi
}

# 显示帮助信息
show_help() {
    cat << HELP
博客项目部署脚本 - 端口10013实例

用法: $0 [命令] [参数]

部署命令:
  deploy              完整部署（前后端）
  deploy-backend      仅部署后端
  deploy-frontend     仅部署前端
  restart             一键重启所有服务

运维命令:
  status              查看服务状态
  logs <服务> [行数]   查看日志 (backend|frontend)
  follow-logs <服务>   实时监控日志 (backend)
  rollback            回滚到上一个版本
  result              查看部署结果记录
  cleanup             清理部署环境（危险操作）

后端管理:
  start-backend       启动后端
  stop-backend        停止后端
  health-backend      后端健康检查

前端管理:
  stop-frontend       停止前端(Nginx)
  health-frontend     前端健康检查

示例:
  $0 deploy                    # 完整部署
  $0 restart                   # 一键重启
  $0 logs backend 100          # 查看后端最近100行日志
  $0 rollback                  # 回滚到上一个版本

HELP
}

# 主函数
case "${1:-help}" in
    deploy)
        full_deploy
        ;;
    deploy-backend)
        deploy_backend_only
        ;;
    deploy-frontend)
        deploy_frontend_only
        ;;
    restart)
        restart_all
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs "${2:-backend}" "${3:-50}"
        ;;
    follow-logs)
        follow_logs "${2:-backend}"
        ;;
    rollback)
        rollback
        ;;
    result)
        show_deploy_result
        ;;
    cleanup)
        cleanup
        ;;
    start-backend)
        bash "${SCRIPT_DIR}/backend.sh" start
        ;;
    stop-backend)
        bash "${SCRIPT_DIR}/backend.sh" stop
        ;;
    health-backend)
        bash "${SCRIPT_DIR}/backend.sh" health
        ;;
    stop-frontend)
        bash "${SCRIPT_DIR}/frontend.sh" stop
        ;;
    health-frontend)
        bash "${SCRIPT_DIR}/frontend.sh" health
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "未知命令: $1"
        show_help
        exit 1
        ;;
esac
