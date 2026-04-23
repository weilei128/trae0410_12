#!/bin/bash
# ============================================
# 前端部署脚本 - 端口10013实例专用
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

# 本地打包前端
clean_local_frontend() {
    log_info "清理本地前端构建目录..."
    cd "${LOCAL_FRONTEND_DIR}" || exit 1
    rm -rf dist node_modules/.cache
    log_success "本地前端清理完成"
}

build_local_frontend() {
    log_info "开始本地前端打包..."
    cd "${LOCAL_FRONTEND_DIR}" || exit 1
    
    # 检查node_modules是否存在
    if [ ! -d "node_modules" ]; then
        log_info "安装前端依赖..."
        npm install
    fi
    
    # 修改vue.config.js中的代理配置为10013端口
    log_info "修改前端代理配置为端口 ${APP_PORT}..."
    cat > vue.config.js << EOF
const { defineConfig } = require('@vue/cli-service')
module.exports = defineConfig({
  transpileDependencies: true,
  devServer: {
    port: ${APP_PORT},
    proxy: {
      '/api': {
        target: 'http://localhost:${APP_PORT}',
        changeOrigin: true
      }
    }
  }
})
EOF
    
    # 执行打包
    npm run build
    
    if [ ! -d "dist" ] || [ ! -f "dist/index.html" ]; then
        log_error "前端打包失败，未找到dist目录或index.html"
        exit 1
    fi
    
    log_success "前端打包完成"
}

# 上传前端文件到服务器
upload_frontend() {
    log_info "上传前端文件到服务器..."
    
    # 创建远程目录
    ssh -p ${SSH_PORT} -i "${SSH_KEY}" ${SERVER_USER}@${SERVER_HOST} \
        "mkdir -p ${FRONTEND_DIR}"
    
    # 上传dist目录内容
    scp -P ${SSH_PORT} -i "${SSH_KEY}" -r \
        "${LOCAL_FRONTEND_DIR}/dist/"* \
        ${SERVER_USER}@${SERVER_HOST}:${FRONTEND_DIR}/
    
    if [ $? -ne 0 ]; then
        log_error "前端文件上传失败"
        exit 1
    fi
    
    log_success "前端文件上传完成"
}

# 生成Nginx配置
generate_nginx_config() {
    log_info "生成Nginx配置文件..."
    
    local nginx_conf_content="# 博客应用 - 端口${APP_PORT}实例配置
# 自动生成于 $(date '+%Y-%m-%d %H:%M:%S')
# 此配置仅服务于端口${APP_PORT}，与其他实例完全隔离

server {
    listen ${APP_PORT};
    server_name _;
    
    # 前端静态文件目录（按端口隔离）
    root ${FRONTEND_DIR};
    index index.html;
    
    # 日志文件（按端口隔离）
    access_log ${LOGS_DIR}/nginx_access.log;
    error_log ${LOGS_DIR}/nginx_error.log;
    
    # 前端页面路由
    location / {
        try_files \$uri \$uri/ /index.html;
        add_header Cache-Control "no-cache, no-store, must-revalidate";
        add_header Pragma "no-cache";
        add_header Expires "0";
    }
    
    # 静态资源缓存
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # API反向代理到后端
    location /api/ {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # 健康检查端点
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
"
    
    # 将配置写入本地临时文件
    echo "${nginx_conf_content}" > "/tmp/blog-${APP_PORT}.conf"
    
    # 上传到服务器
    scp -P ${SSH_PORT} -i "${SSH_KEY}" \
        "/tmp/blog-${APP_PORT}.conf" \
        ${SERVER_USER}@${SERVER_HOST}:${NGINX_CONF_FILE}
    
    rm -f "/tmp/blog-${APP_PORT}.conf"
    
    log_success "Nginx配置文件生成完成"
}

# 应用Nginx配置
apply_nginx_config() {
    log_info "应用Nginx配置..."
    
    ssh -p ${SSH_PORT} -i "${SSH_KEY}" ${SERVER_USER}@${SERVER_HOST} << EOF
        # 创建软链接到sites-enabled
        if [ -d ${NGINX_SITES_ENABLED} ]; then
            ln -sf ${NGINX_CONF_FILE} ${NGINX_SITES_ENABLED}/blog-${APP_PORT}.conf
        fi
        
        # 测试Nginx配置
        nginx -t 2>&1
        if [ \$? -eq 0 ]; then
            # 重载Nginx
            systemctl reload nginx || nginx -s reload 2>/dev/null || service nginx reload
            echo "Nginx配置已应用并重载"
        else
            echo "Nginx配置测试失败"
            exit 1
        fi
EOF
    
    if [ $? -ne 0 ]; then
        log_error "Nginx配置应用失败"
        exit 1
    fi
    
    log_success "Nginx配置应用完成"
}

# 停止Nginx服务（仅影响当前端口）
stop_nginx() {
    log_info "停止端口 ${APP_PORT} 的Nginx服务..."
    
    ssh -p ${SSH_PORT} -i "${SSH_KEY}" ${SERVER_USER}@${SERVER_HOST} << EOF
        # 移除当前端口的配置
        rm -f ${NGINX_SITES_ENABLED}/blog-${APP_PORT}.conf
        
        # 重载Nginx
        systemctl reload nginx 2>/dev/null || nginx -s reload 2>/dev/null || service nginx reload 2>/dev/null
        echo "端口 ${APP_PORT} 的Nginx配置已移除"
EOF
    
    log_success "Nginx配置已移除"
}

# 健康检查
check_health() {
    log_info "执行前端健康检查..."
    
    local retry_count=0
    local max_retries=6
    
    while [ $retry_count -lt $max_retries ]; do
        local http_code=$(ssh -p ${SSH_PORT} -i "${SSH_KEY}" ${SERVER_USER}@${SERVER_HOST} \
            "curl -s -o /dev/null -w '%{http_code}' http://localhost:${APP_PORT}/index.html 2>/dev/null || echo '000'")
        
        if [ "$http_code" = "200" ]; then
            log_success "前端健康检查通过 (HTTP ${http_code})"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        log_warn "前端健康检查失败 (HTTP ${http_code})，第 ${retry_count}/${max_retries} 次重试..."
        sleep 3
    done
    
    log_error "前端健康检查失败"
    return 1
}

# 主函数
case "${1:-deploy}" in
    build)
        build_local_frontend
        ;;
    upload)
        upload_frontend
        ;;
    nginx-config)
        generate_nginx_config
        apply_nginx_config
        ;;
    stop)
        stop_nginx
        ;;
    health)
        check_health
        ;;
    deploy)
        clean_local_frontend
        build_local_frontend
        upload_frontend
        generate_nginx_config
        apply_nginx_config
        check_health
        ;;
    *)
        echo "用法: $0 {build|upload|nginx-config|stop|health|deploy}"
        exit 1
        ;;
esac
