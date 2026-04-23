#!/bin/bash
# ============================================
# 后端部署脚本 - 端口10013实例专用
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

# 本地打包后端
clean_local_backend() {
    log_info "清理本地后端构建目录..."
    cd "${LOCAL_BACKEND_DIR}" || exit 1
    if [ -f "pom.xml" ]; then
        mvn clean -q
        log_success "本地后端清理完成"
    else
        log_warn "未找到pom.xml，跳过清理"
    fi
}

build_local_backend() {
    log_info "开始本地后端打包..."
    cd "${LOCAL_BACKEND_DIR}" || exit 1
    
    # 修改application.properties为10013端口
    log_info "修改后端端口为 ${APP_PORT}..."
    echo "server.port=${APP_PORT}" > src/main/resources/application.properties
    
    # 执行打包
    mvn clean package -DskipTests -q
    
    if [ ! -f "target/${JAR_NAME}" ]; then
        log_error "后端打包失败，未找到JAR文件"
        exit 1
    fi
    
    log_success "后端打包完成: target/${JAR_NAME}"
}

# 在服务器上创建目录结构
setup_server_dirs() {
    log_info "创建服务器目录结构..."
    
    ssh -p ${SSH_PORT} -i "${SSH_KEY}" ${SERVER_USER}@${SERVER_HOST} << EOF
        mkdir -p ${BACKEND_DIR} ${LOGS_DIR} ${BACKUP_DIR} ${NGINX_CONF_DIR}
        echo "目录创建完成"
EOF
    
    log_success "服务器目录结构创建完成"
}

# 备份当前运行版本
backup_current_version() {
    log_info "备份当前版本..."
    
    local backup_time=$(date '+%Y%m%d_%H%M%S')
    local backup_path="${BACKUP_DIR}/${backup_time}"
    
    ssh -p ${SSH_PORT} -i "${SSH_KEY}" ${SERVER_USER}@${SERVER_HOST} << EOF
        if [ -f ${JAR_PATH} ]; then
            mkdir -p ${backup_path}
            cp ${JAR_PATH} ${backup_path}/
            echo "BACKUP_PATH=${backup_path}" > ${BASE_DIR}/.last_backup
            echo "备份完成: ${backup_path}"
        else
            echo "没有现有版本需要备份"
        fi
EOF
    
    log_success "备份完成"
}

# 上传JAR包到服务器
upload_backend() {
    log_info "上传JAR包到服务器..."
    
    scp -P ${SSH_PORT} -i "${SSH_KEY}" \
        "${LOCAL_BACKEND_DIR}/target/${JAR_NAME}" \
        ${SERVER_USER}@${SERVER_HOST}:${BACKEND_DIR}/
    
    if [ $? -ne 0 ]; then
        log_error "JAR包上传失败"
        exit 1
    fi
    
    log_success "JAR包上传完成"
}

# 严格查杀占用10013端口的进程（仅针对本项目）
kill_port_processes() {
    log_info "查杀占用端口 ${APP_PORT} 的进程..."
    
    ssh -p ${SSH_PORT} -i "${SSH_KEY}" ${SERVER_USER}@${SERVER_HOST} << EOF
        # 查找占用指定端口的进程PID（精确匹配）
        PIDS=\$(netstat -tlnp 2>/dev/null | grep ":${APP_PORT}" | awk '{print \$7}' | cut -d'/' -f1 | grep -E '^[0-9]+\$' | sort -u)
        
        if [ -n "\$PIDS" ]; then
            echo "发现占用端口 ${APP_PORT} 的进程: \$PIDS"
            for PID in \$PIDS; do
                # 获取进程详细信息，验证是否为Java进程（本项目）
                CMDLINE=\$(cat /proc/\$PID/cmdline 2>/dev/null | tr '\0' ' ')
                if echo "\$CMDLINE" | grep -q "todo-app.*${APP_PORT}"; then
                    echo "终止本项目进程 PID=\$PID"
                    kill -15 \$PID 2>/dev/null
                    sleep 2
                    # 强制终止如果还在运行
                    if kill -0 \$PID 2>/dev/null; then
                        kill -9 \$PID 2>/dev/null
                    fi
                else
                    echo "进程 \$PID 不是本项目进程，跳过（安全保护）"
                fi
            done
        else
            echo "端口 ${APP_PORT} 未被占用"
        fi
        
        # 清理PID文件
        rm -f ${PID_FILE}
EOF
    
    log_success "端口 ${APP_PORT} 进程清理完成"
}

# 启动后端服务
start_backend() {
    log_info "启动后端服务..."
    
    ssh -p ${SSH_PORT} -i "${SSH_KEY}" ${SERVER_USER}@${SERVER_HOST} << EOF
        cd ${BACKEND_DIR}
        
        # 使用nohup启动，输出到日志文件
        nohup java -jar ${JAR_NAME} \
            --server.port=${APP_PORT} \
            > ${APP_LOG} 2>&1 &
        
        # 记录PID
        echo \$! > ${PID_FILE}
        echo "服务已启动，PID: \$(cat ${PID_FILE})"
EOF
    
    log_success "后端服务启动命令已执行"
    
    # 等待服务启动
    log_info "等待服务启动（5秒）..."
    sleep 5
}

# 停止后端服务
stop_backend() {
    log_info "停止后端服务..."
    
    ssh -p ${SSH_PORT} -i "${SSH_KEY}" ${SERVER_USER}@${SERVER_HOST} << EOF
        if [ -f ${PID_FILE} ]; then
            PID=\$(cat ${PID_FILE})
            if kill -0 \$PID 2>/dev/null; then
                echo "正在停止进程 PID=\$PID"
                kill -15 \$PID
                sleep 3
                # 强制终止如果还在运行
                if kill -0 \$PID 2>/dev/null; then
                    kill -9 \$PID
                fi
                echo "服务已停止"
            else
                echo "进程已不存在"
            fi
            rm -f ${PID_FILE}
        else
            echo "PID文件不存在，尝试通过端口查找..."
            # 通过端口查找并终止
            PIDS=\$(netstat -tlnp 2>/dev/null | grep ":${APP_PORT}" | awk '{print \$7}' | cut -d'/' -f1 | grep -E '^[0-9]+\$')
            for PID in \$PIDS; do
                CMDLINE=\$(cat /proc/\$PID/cmdline 2>/dev/null | tr '\0' ' ')
                if echo "\$CMDLINE" | grep -q "todo-app"; then
                    kill -15 \$PID 2>/dev/null
                    sleep 2
                    kill -9 \$PID 2>/dev/null
                    echo "已终止进程 PID=\$PID"
                fi
            done
        fi
EOF
    
    log_success "后端服务停止完成"
}

# 查看实时日志
tail_logs() {
    log_info "查看实时日志（按Ctrl+C退出）..."
    
    ssh -p ${SSH_PORT} -i "${SSH_KEY}" ${SERVER_USER}@${SERVER_HOST} \
        "tail -f ${APP_LOG}"
}

# 查看日志（最后100行）
view_logs() {
    local lines=${1:-100}
    log_info "查看最近 ${lines} 行日志..."
    
    ssh -p ${SSH_PORT} -i "${SSH_KEY}" ${SERVER_USER}@${SERVER_HOST} \
        "tail -n ${lines} ${APP_LOG}"
}

# 检查服务状态
check_status() {
    log_info "检查后端服务状态..."
    
    ssh -p ${SSH_PORT} -i "${SSH_KEY}" ${SERVER_USER}@${SERVER_HOST} << EOF
        if [ -f ${PID_FILE} ]; then
            PID=\$(cat ${PID_FILE})
            if kill -0 \$PID 2>/dev/null; then
                echo "服务运行中 - PID: \$PID"
                echo "端口监听状态:"
                netstat -tlnp 2>/dev/null | grep ":${APP_PORT}" || ss -tlnp | grep ":${APP_PORT}"
            else
                echo "服务未运行（PID文件存在但进程不存在）"
            fi
        else
            echo "服务未运行（无PID文件）"
        fi
EOF
}

# 健康检查
check_health() {
    log_info "执行后端健康检查..."
    
    local retry_count=0
    local max_retries=6
    
    while [ $retry_count -lt $max_retries ]; do
        local http_code=$(ssh -p ${SSH_PORT} -i "${SSH_KEY}" ${SERVER_USER}@${SERVER_HOST} \
            "curl -s -o /dev/null -w '%{http_code}' ${BACKEND_HEALTH_URL} 2>/dev/null || echo '000'")
        
        if [ "$http_code" = "200" ]; then
            log_success "后端健康检查通过 (HTTP ${http_code})"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        log_warn "健康检查失败 (HTTP ${http_code})，第 ${retry_count}/${max_retries} 次重试..."
        sleep 5
    done
    
    log_error "后端健康检查失败，服务可能未正常启动"
    return 1
}

# 回滚到上一个版本
rollback() {
    log_info "执行回滚操作..."
    
    ssh -p ${SSH_PORT} -i "${SSH_KEY}" ${SERVER_USER}@${SERVER_HOST} << EOF
        if [ -f ${BASE_DIR}/.last_backup ]; then
            source ${BASE_DIR}/.last_backup
            if [ -n "\$BACKUP_PATH" ] && [ -f \${BACKUP_PATH}/${JAR_NAME} ]; then
                # 停止当前服务
                if [ -f ${PID_FILE} ]; then
                    PID=\$(cat ${PID_FILE})
                    kill -15 \$PID 2>/dev/null
                    sleep 2
                    kill -9 \$PID 2>/dev/null
                    rm -f ${PID_FILE}
                fi
                
                # 恢复备份
                cp \${BACKUP_PATH}/${JAR_NAME} ${JAR_PATH}
                echo "已恢复到备份: \$BACKUP_PATH"
                
                # 重新启动
                cd ${BACKEND_DIR}
                nohup java -jar ${JAR_NAME} --server.port=${APP_PORT} > ${APP_LOG} 2>&1 &
                echo \$! > ${PID_FILE}
                echo "回滚完成，服务已重新启动"
            else
                echo "备份文件不存在，无法回滚"
                exit 1
            fi
        else
            echo "没有找到备份记录，无法回滚"
            exit 1
        fi
EOF
    
    log_success "回滚操作完成"
}

# 主函数
case "${1:-deploy}" in
    build)
        build_local_backend
        ;;
    upload)
        upload_backend
        ;;
    start)
        start_backend
        ;;
    stop)
        stop_backend
        ;;
    restart)
        stop_backend
        sleep 2
        start_backend
        ;;
    status)
        check_status
        ;;
    logs)
        tail_logs
        ;;
    view-logs)
        view_logs "${2:-100}"
        ;;
    kill-port)
        kill_port_processes
        ;;
    health)
        check_health
        ;;
    rollback)
        rollback
        ;;
    deploy)
        clean_local_backend
        build_local_backend
        setup_server_dirs
        backup_current_version
        kill_port_processes
        upload_backend
        start_backend
        check_health
        ;;
    *)
        echo "用法: $0 {build|upload|start|stop|restart|status|logs|view-logs [行数]|kill-port|health|rollback|deploy}"
        exit 1
        ;;
esac
