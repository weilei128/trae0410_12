#!/bin/bash
# ============================================
# 远程服务器部署脚本（简化版）- 端口10013实例专用
# Nginx使用10013对外服务，后端使用10014内部端口
# ============================================

set -e

# 配置
APP_PORT=10013
BACKEND_INTERNAL_PORT=10014
BASE_DIR="/opt/blog-app/${APP_PORT}"
BACKEND_DIR="${BASE_DIR}/backend"
FRONTEND_DIR="${BASE_DIR}/frontend"
LOGS_DIR="${BASE_DIR}/logs"
NGINX_CONF_DIR="${BASE_DIR}/nginx"
BACKUP_DIR="${BASE_DIR}/backup"
SOURCE_DIR="${BASE_DIR}/source"

JAR_NAME="todo-app-1.0.0.jar"
APP_LOG="${LOGS_DIR}/app.log"
PID_FILE="${BASE_DIR}/app.pid"
DEPLOY_RESULT_FILE="${BASE_DIR}/.deploy_result"

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

# 创建目录结构
setup_directories() {
    log_info "创建目录结构..."
    mkdir -p ${BACKEND_DIR} ${FRONTEND_DIR} ${LOGS_DIR} ${NGINX_CONF_DIR} ${BACKUP_DIR}
    log_success "目录结构创建完成"
}

# 备份当前版本
backup_current() {
    log_info "备份当前版本..."
    
    if [ -f "${BACKEND_DIR}/${JAR_NAME}" ]; then
        local backup_time=$(date '+%Y%m%d_%H%M%S')
        local backup_path="${BACKUP_DIR}/${backup_time}"
        mkdir -p ${backup_path}
        cp ${BACKEND_DIR}/${JAR_NAME} ${backup_path}/
        echo "BACKUP_PATH=${backup_path}" > ${BASE_DIR}/.last_backup
        log_success "备份完成: ${backup_path}"
    else
        log_warn "没有现有版本需要备份"
    fi
}

# 严格查杀占用后端端口的进程（仅针对本项目）
kill_backend_port() {
    log_info "查杀占用后端端口 ${BACKEND_INTERNAL_PORT} 的进程..."
    
    # 查找占用指定端口的进程PID（精确匹配）
    local PIDS=$(netstat -tlnp 2>/dev/null | grep ":${BACKEND_INTERNAL_PORT}" | awk '{print $7}' | cut -d'/' -f1 | grep -E '^[0-9]+$' | sort -u)
    
    if [ -n "$PIDS" ]; then
        log_warn "发现占用端口 ${BACKEND_INTERNAL_PORT} 的进程: $PIDS"
        for PID in $PIDS; do
            # 获取进程详细信息，验证是否为Java进程（本项目）
            local CMDLINE=$(cat /proc/$PID/cmdline 2>/dev/null | tr '\0' ' ')
            if echo "$CMDLINE" | grep -q "todo-app\|java.*${BACKEND_INTERNAL_PORT}"; then
                log_info "终止本项目进程 PID=$PID"
                kill -15 $PID 2>/dev/null || true
                sleep 2
                # 强制终止如果还在运行
                if kill -0 $PID 2>/dev/null; then
                    kill -9 $PID 2>/dev/null || true
                fi
            else
                log_warn "进程 $PID 不是本项目进程，跳过（安全保护）"
            fi
        done
    else
        log_info "端口 ${BACKEND_INTERNAL_PORT} 未被占用"
    fi
    
    # 清理PID文件
    rm -f ${PID_FILE}
    log_success "端口 ${BACKEND_INTERNAL_PORT} 进程清理完成"
}

# 部署后端（使用预编译JAR）
deploy_backend() {
    log_info "部署后端..."
    
    local jar_source="${SOURCE_DIR}/backend/target/${JAR_NAME}"
    
    if [ ! -f "${jar_source}" ]; then
        log_error "JAR包不存在: ${jar_source}"
        exit 1
    fi
    
    # 复制JAR到部署目录
    cp ${jar_source} ${BACKEND_DIR}/
    log_success "后端JAR部署完成"
}

# 构建前端
build_frontend() {
    log_info "构建前端..."
    
    local frontend_src="${SOURCE_DIR}/frontend"
    
    if [ ! -d "${frontend_src}" ]; then
        log_error "前端源码不存在: ${frontend_src}"
        exit 1
    fi
    
    cd ${frontend_src}
    
    # 修改vue.config.js中的代理配置
    log_info "修改前端代理配置..."
    cat > vue.config.js << 'EOF'
const { defineConfig } = require('@vue/cli-service')
module.exports = defineConfig({
  transpileDependencies: true,
  devServer: {
    port: 10014,
    proxy: {
      '/api': {
        target: 'http://localhost:10014',
        changeOrigin: true
      }
    }
  }
})
EOF
    
    # 安装依赖并构建
    log_info "安装前端依赖..."
    npm install
    
    log_info "执行前端打包..."
    npm run build
    
    if [ ! -d "dist" ] || [ ! -f "dist/index.html" ]; then
        log_error "前端打包失败"
        exit 1
    fi
    
    # 复制到部署目录
    rm -rf ${FRONTEND_DIR}/*
    cp -r dist/* ${FRONTEND_DIR}/
    log_success "前端构建完成"
}

# 启动后端
start_backend() {
    log_info "启动后端服务..."
    
    cd ${BACKEND_DIR}
    
    # 使用nohup启动，指定内部端口
    nohup java -jar ${JAR_NAME} \
        --server.port=${BACKEND_INTERNAL_PORT} \
        > ${APP_LOG} 2>&1 &
    
    echo $! > ${PID_FILE}
    log_success "后端服务已启动，PID: $(cat ${PID_FILE})"
    
    # 等待服务启动
    log_info "等待服务启动（5秒）..."
    sleep 5
}

# 停止后端
stop_backend() {
    log_info "停止后端服务..."
    
    if [ -f ${PID_FILE} ]; then
        local PID=$(cat ${PID_FILE})
        if kill -0 $PID 2>/dev/null; then
            kill -15 $PID
            sleep 3
            if kill -0 $PID 2>/dev/null; then
                kill -9 $PID
            fi
            log_success "后端服务已停止"
        else
            log_warn "进程已不存在"
        fi
        rm -f ${PID_FILE}
    else
        log_warn "PID文件不存在"
    fi
}

# 生成Nginx配置
generate_nginx_config() {
    log_info "生成Nginx配置..."
    
    cat > ${NGINX_CONF_DIR}/blog-${APP_PORT}.conf << EOF
# 博客应用 - 端口${APP_PORT}实例配置
# Nginx监听10013端口，后端使用10014端口
server {
    listen ${APP_PORT};
    server_name _;
    
    root ${FRONTEND_DIR};
    index index.html;
    
    access_log ${LOGS_DIR}/nginx_access.log;
    error_log ${LOGS_DIR}/nginx_error.log;
    
    location / {
        try_files \$uri \$uri/ /index.html;
        add_header Cache-Control "no-cache, no-store, must-revalidate";
        add_header Pragma "no-cache";
        add_header Expires "0";
    }
    
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    location /api/ {
        proxy_pass http://127.0.0.1:${BACKEND_INTERNAL_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF
    
    # 创建软链接
    if [ -d /etc/nginx/sites-enabled ]; then
        ln -sf ${NGINX_CONF_DIR}/blog-${APP_PORT}.conf /etc/nginx/sites-enabled/
    fi
    
    log_success "Nginx配置生成完成"
}

# 应用Nginx配置
apply_nginx_config() {
    log_info "应用Nginx配置..."
    
    nginx -t 2>&1
    if [ $? -eq 0 ]; then
        systemctl reload nginx 2>/dev/null || nginx -s reload 2>/dev/null || service nginx reload
        log_success "Nginx配置已应用"
    else
        log_error "Nginx配置测试失败"
        exit 1
    fi
}

# 健康检查
check_health() {
    log_info "执行健康检查..."
    
    local backend_ok=false
    local frontend_ok=false
    
    # 后端健康检查
    log_info "检查后端API..."
    local retry=0
    while [ $retry -lt 6 ]; do
        local http_code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:${BACKEND_INTERNAL_PORT}/api/todos 2>/dev/null || echo '000')
        if [ "$http_code" = "200" ]; then
            backend_ok=true
            log_success "后端健康检查通过 (HTTP ${http_code})"
            break
        fi
        retry=$((retry + 1))
        log_warn "后端健康检查失败 (HTTP ${http_code})，重试 ${retry}/6..."
        sleep 5
    done
    
    # 前端健康检查（通过Nginx）
    log_info "检查前端页面..."
    retry=0
    while [ $retry -lt 6 ]; do
        local http_code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:${APP_PORT}/index.html 2>/dev/null || echo '000')
        if [ "$http_code" = "200" ]; then
            frontend_ok=true
            log_success "前端健康检查通过 (HTTP ${http_code})"
            break
        fi
        retry=$((retry + 1))
        log_warn "前端健康检查失败 (HTTP ${http_code})，重试 ${retry}/6..."
        sleep 3
    done
    
    if [ "$backend_ok" = true ] && [ "$frontend_ok" = true ]; then
        return 0
    else
        return 1
    fi
}

# 记录部署结果
record_deploy_result() {
    local status=$1
    local message=$2
    local deploy_time=$(date '+%Y-%m-%d %H:%M:%S')
    local server_ip=$(hostname -I | awk '{print $1}')
    
    cat > ${DEPLOY_RESULT_FILE} << RESULT
{
    "deploy_time": "${deploy_time}",
    "port": "${APP_PORT}",
    "status": "${status}",
    "message": "${message}",
    "frontend_url": "http://${server_ip}:${APP_PORT}",
    "backend_url": "http://${server_ip}:${APP_PORT}/api/todos"
}
RESULT
    log_info "部署结果已记录"
}

# 回滚
rollback() {
    log_info "执行回滚..."
    
    if [ -f ${BASE_DIR}/.last_backup ]; then
        source ${BASE_DIR}/.last_backup
        if [ -n "$BACKUP_PATH" ] && [ -f ${BACKUP_PATH}/${JAR_NAME} ]; then
            stop_backend
            cp ${BACKUP_PATH}/${JAR_NAME} ${BACKEND_DIR}/
            start_backend
            apply_nginx_config
            log_success "回滚完成"
            record_deploy_result "ROLLED_BACK" "已回滚到上一个版本"
        else
            log_error "备份文件不存在"
            exit 1
        fi
    else
        log_error "没有找到备份记录"
        exit 1
    fi
}

# 完整部署
full_deploy() {
    local deploy_start=$(date +%s)
    
    log_info "========== 开始部署端口 ${APP_PORT} 实例 =========="
    
    setup_directories
    backup_current
    kill_backend_port
    deploy_backend
    build_frontend
    generate_nginx_config
    start_backend
    apply_nginx_config
    
    if check_health; then
        local deploy_end=$(date +%s)
        local duration=$((deploy_end - deploy_start))
        
        record_deploy_result "SUCCESS" "部署成功"
        
        echo ""
        echo "=========================================="
        log_success "部署成功！"
        echo ""
        local server_ip=$(hostname -I | awk '{print $1}')
        echo "访问地址:"
        echo "  前端: http://${server_ip}:${APP_PORT}"
        echo "  后端: http://${server_ip}:${APP_PORT}/api/todos"
        echo ""
        echo "部署耗时: ${duration} 秒"
        echo "=========================================="
    else
        record_deploy_result "FAILED" "健康检查失败"
        log_error "部署失败，健康检查未通过"
        exit 1
    fi
}

# 一键重启
restart_all() {
    log_info "一键重启..."
    stop_backend
    sleep 2
    start_backend
    apply_nginx_config
    check_health
    log_success "重启完成"
}

# 查看状态
show_status() {
    echo "========== 服务状态 =========="
    echo ""
    
    if [ -f ${PID_FILE} ]; then
        local PID=$(cat ${PID_FILE})
        if kill -0 $PID 2>/dev/null; then
            echo "后端状态: 运行中 (PID: $PID)"
        else
            echo "后端状态: 未运行"
        fi
    else
        echo "后端状态: 未运行"
    fi
    
    echo ""
    echo "端口监听情况:"
    echo "Nginx (10013):"
    netstat -tlnp 2>/dev/null | grep ":10013" || ss -tlnp | grep ":10013" || echo "无"
    echo "后端 (10014):"
    netstat -tlnp 2>/dev/null | grep ":10014" || ss -tlnp | grep ":10014" || echo "无"
    
    echo ""
    echo "部署目录:"
    ls -la ${BASE_DIR}/
}

# 查看日志
view_logs() {
    local service=$1
    local lines=${2:-50}
    
    case $service in
        backend)
            tail -n ${lines} ${APP_LOG}
            ;;
        nginx)
            tail -n ${lines} ${LOGS_DIR}/nginx_error.log
            ;;
        *)
            echo "用法: $0 logs {backend|nginx} [行数]"
            ;;
    esac
}

# 主函数
case "${1:-deploy}" in
    deploy)
        full_deploy
        ;;
    restart)
        restart_all
        ;;
    stop)
        stop_backend
        ;;
    start)
        start_backend
        ;;
    status)
        show_status
        ;;
    logs)
        view_logs "${2:-backend}" "${3:-50}"
        ;;
    rollback)
        rollback
        ;;
    health)
        check_health
        ;;
    kill-port)
        kill_backend_port
        ;;
    *)
        echo "用法: $0 {deploy|restart|stop|start|status|logs|rollback|health|kill-port}"
        exit 1
        ;;
esac
