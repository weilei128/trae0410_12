#!/bin/bash
# ============================================
# 部署配置文件 - 端口10013实例专用
# ============================================

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 服务器配置
SERVER_HOST="49.235.161.106"
SERVER_USER="root"
SSH_PORT=22
SSH_KEY="${HOME}/.ssh/id_rsa"

# 端口配置（严格固定10013）
APP_PORT=10013

# 服务器上的独立目录结构（按端口隔离）
BASE_DIR="/opt/blog-app/${APP_PORT}"
BACKEND_DIR="${BASE_DIR}/backend"
FRONTEND_DIR="${BASE_DIR}/frontend"
LOGS_DIR="${BASE_DIR}/logs"
NGINX_CONF_DIR="${BASE_DIR}/nginx"
BACKUP_DIR="${BASE_DIR}/backup"

# 本地项目路径
LOCAL_BACKEND_DIR="${PROJECT_ROOT}/backend"
LOCAL_FRONTEND_DIR="${PROJECT_ROOT}/frontend"

# JAR包配置
JAR_NAME="todo-app-1.0.0.jar"
JAR_PATH="${BACKEND_DIR}/${JAR_NAME}"

# 日志文件
APP_LOG="${LOGS_DIR}/app.log"
DEPLOY_LOG="${LOGS_DIR}/deploy.log"
PID_FILE="${BASE_DIR}/app.pid"

# Nginx配置
NGINX_CONF_FILE="${NGINX_CONF_DIR}/blog-${APP_PORT}.conf"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"

# 健康检查配置
HEALTH_CHECK_TIMEOUT=30
BACKEND_HEALTH_URL="http://localhost:${APP_PORT}/api/todos"
FRONTEND_HEALTH_URL="http://localhost:${APP_PORT}"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
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
