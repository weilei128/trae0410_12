$SERVER = "49.235.161.106"
$SSH_PORT = "22"
$SSH_USER = "root"
$PORT = "10012"
$PROJECT_NAME = "blog"
$DEPLOY_BASE = "/opt/projects/${PROJECT_NAME}_${PORT}"
$DEPLOY_LOG = "/opt/deploy_logs/${PROJECT_NAME}_${PORT}.log"

function Log {
    param([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $message"
}

function Invoke-SSH {
    param([string]$command)
    $result = ssh -p $SSH_PORT "${SSH_USER}@${SERVER}" $command 2>&1
    return $result
}

Log "========================================="
Log "停止服务 ${PROJECT_NAME} 端口: ${PORT}"
Log "========================================="

$script = @"
stopped=false

if [ -f ${DEPLOY_BASE}/backend/app.pid ]; then
    pid=\$(cat ${DEPLOY_BASE}/backend/app.pid)
    if [ -n \"\$pid\" ] && ps -p \$pid > /dev/null 2>&1; then
        cmd=\$(ps -p \$pid -o args= 2>/dev/null || echo '')
        if echo \"\$cmd\" | grep -qE 'java.*${PORT}'; then
            echo '找到后端服务进程 PID: '\$pid
            kill -15 \$pid
            sleep 3
            
            if ps -p \$pid > /dev/null 2>&1; then
                echo '进程未响应SIGTERM，强制终止...'
                kill -9 \$pid
                sleep 1
            fi
            
            if ! ps -p \$pid > /dev/null 2>&1; then
                echo '✓ 后端服务已停止'
                stopped=true
            fi
        else
            echo '警告: PID文件中的进程不是本项目服务'
        fi
    else
        echo 'PID文件中的进程已不存在'
    fi
    rm -f ${DEPLOY_BASE}/backend/app.pid
fi

if [ \"\$stopped\" = false ]; then
    echo '尝试通过端口 ${PORT} 查找进程...'
    pids=\$(netstat -tlnp 2>/dev/null | grep ':${PORT} ' | awk '{print \$7}' | cut -d'/' -f1 | grep -v '-' | sort -u)
    
    for pid in \$pids; do
        if [ -n \"\$pid\" ]; then
            cmd=\$(ps -p \$pid -o args= 2>/dev/null || echo '')
            if echo \"\$cmd\" | grep -qE 'java|node'; then
                echo '找到端口 ${PORT} 上的进程 PID: '\$pid
                kill -15 \$pid
                sleep 2
                if ps -p \$pid > /dev/null 2>&1; then
                    kill -9 \$pid
                fi
                echo '✓ 进程已停止'
                stopped=true
            fi
        fi
    done
fi

if [ \"\$stopped\" = false ]; then
    echo '未找到运行中的服务'
fi

echo ''
echo '端口 ${PORT} 状态:'
netstat -tlnp 2>/dev/null | grep ':${PORT} ' || echo '端口 ${PORT} 已释放'
"@

Invoke-SSH $script | ForEach-Object { Log $_ }

Log "========================================="
Log "停止操作完成"
Log "========================================="
