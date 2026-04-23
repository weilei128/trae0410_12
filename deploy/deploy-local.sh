#!/bin/bash
# ============================================
# 本地部署入口脚本 - 端口10013实例专用
# 功能：上传代码到服务器，触发远程部署
# ============================================

set -e

# 配置
SERVER_HOST="49.235.161.106"
SERVER_USER="root"
SSH_PORT=22
SSH_KEY="${HOME}/.ssh/id_rsa"
APP_PORT=10013

# 本地路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
REMOTE_BASE_DIR="/opt/blog-app/${APP_PORT}"
REMOTE_SOURCE_DIR="${REMOTE_BASE_DIR}/source"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# 检查SSH连接
check_ssh() {
    log_info "检查SSH连接..."
    if ! ssh -p ${SSH_PORT} -i "${SSH_KEY}" -o ConnectTimeout=5 ${SERVER_USER}@${SERVER_HOST} "echo 'SSH OK'" > /dev/null 2>&1; then
        log_error "SSH连接失败，请检查："
        log_error "  1. SSH密钥是否配置正确"
        log_error "  2. 服务器地址和端口是否正确"
        log_error "  3. 网络连接是否正常"
        exit 1
    fi
    log_success "SSH连接正常"
}

# 上传源代码
upload_source() {
    log_info "上传源代码到服务器..."
    
    # 创建远程目录
    ssh -p ${SSH_PORT} -i "${SSH_KEY}" ${SERVER_USER}@${SERVER_HOST} "mkdir -p ${REMOTE_SOURCE_DIR}"
    
    # 上传后端代码（排除target目录）
    log_info "上传后端代码..."
    rsync -avz -e "ssh -p ${SSH_PORT} -i ${SSH_KEY}" \
        --exclude='target' \
        --exclude='.git' \
        "${PROJECT_ROOT}/backend/" \
        ${SERVER_USER}@${SERVER_HOST}:${REMOTE_SOURCE_DIR}/backend/
    
    # 上传前端代码（排除node_modules和dist）
    log_info "上传前端代码..."
    rsync -avz -e "ssh -p ${SSH_PORT} -i ${SSH_KEY}" \
        --exclude='node_modules' \
        --exclude='dist' \
        --exclude='.git' \
        "${PROJECT_ROOT}/frontend/" \
        ${SERVER_USER}@${SERVER_HOST}:${REMOTE_SOURCE_DIR}/frontend/
    
    # 上传远程部署脚本
    log_info "上传部署脚本..."
    scp -P ${SSH_PORT} -i "${SSH_KEY}" \
        "${SCRIPT_DIR}/remote-deploy.sh" \
        ${SERVER_USER}@${SERVER_HOST}:${REMOTE_BASE_DIR}/
    
    log_success "代码上传完成"
}

# 执行远程部署
execute_remote_deploy() {
    log_info "在服务器上执行部署..."
    
    ssh -p ${SSH_PORT} -i "${SSH_KEY}" ${SERVER_USER}@${SERVER_HOST} \
        "cd ${REMOTE_BASE_DIR} && bash remote-deploy.sh deploy"
}

# 执行远程命令
execute_remote() {
    local cmd=$1
    ssh -p ${SSH_PORT} -i "${SSH_KEY}" ${SERVER_USER}@${SERVER_HOST} \
        "cd ${REMOTE_BASE_DIR} && bash remote-deploy.sh ${cmd}"
}

# 完整部署
full_deploy() {
    echo ""
    echo "=========================================="
    echo "  博客项目部署 - 端口 ${APP_PORT} 实例"
    echo "=========================================="
    echo ""
    
    check_ssh
    upload_source
    execute_remote_deploy
    
    echo ""
    echo "=========================================="
    log_success "本地部署流程完成"
    echo "=========================================="
}

# 显示帮助
show_help() {
    cat << HELP
博客项目部署脚本 - 端口10013实例

用法: $0 [命令]

部署命令:
  deploy              完整部署（上传代码+构建+部署）
  
远程运维命令（无需上传代码）:
  restart             一键重启
  stop                停止服务
  start               启动服务
  status              查看状态
  logs [服务] [行数]   查看日志 (backend|nginx)
  rollback            回滚到上一个版本
  health              健康检查

示例:
  $0 deploy                    # 完整部署
  $0 restart                   # 一键重启
  $0 logs backend 100          # 查看后端最近100行日志
  $0 rollback                  # 回滚

HELP
}

# 主函数
case "${1:-deploy}" in
    deploy)
        full_deploy
        ;;
    restart|stop|start|status|rollback|health)
        check_ssh
        execute_remote "$1"
        ;;
    logs)
        check_ssh
        execute_remote "logs ${2:-backend} ${3:-50}"
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
