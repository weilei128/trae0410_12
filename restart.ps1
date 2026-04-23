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
Log "重启服务 ${PROJECT_NAME} 端口: ${PORT}"
Log "========================================="

Log "停止后端服务..."
$stopScript = @"
if [ -f ${DEPLOY_BASE}/backend/app.pid ]; then
    pid=\$(cat ${DEPLOY_BASE}/backend/app.pid)
    if ps -p \$pid > /dev/null 2>&1; then
        kill -15 \$pid
        sleep 3
        if ps -p \$pid > /dev/null 2>&1; then
            kill -9 \$pid
        fi
        echo '后端服务已停止 (PID: '\$pid')'
    else
        echo '后端服务未运行'
    fi
    rm -f ${DEPLOY_BASE}/backend/app.pid
else
    echo 'PID文件不存在，尝试通过端口查找进程'
    pid=\$(netstat -tlnp 2>/dev/null | grep ':${PORT} ' | awk '{print \$7}' | cut -d'/' -f1 | head -1)
    if [ -n \"\$pid\" ] && [ \"\$pid\" != \"-\" ]; then
        kill -15 \$pid
        sleep 2
        echo '已终止端口 ${PORT} 上的进程 (PID: '\$pid')'
    else
        echo '未找到运行中的服务'
    fi
fi
"@
Invoke-SSH $stopScript | ForEach-Object { Log $_ }

Start-Sleep -Seconds 2

Log "启动后端服务..."
$startScript = @"
cd ${DEPLOY_BASE}/backend
JAR_NAME=\$(ls *.jar 2>/dev/null | grep -v '\.original' | head -1)

if [ -z \"\$JAR_NAME\" ]; then
    echo '错误: 未找到JAR包'
    exit 1
fi

nohup java -Xms128m -Xmx256m -jar \$JAR_NAME --server.port=${PORT} > ${DEPLOY_BASE}/logs/app.log 2>&1 &
echo \$! > ${DEPLOY_BASE}/backend/app.pid
sleep 3

if ps -p \$(cat ${DEPLOY_BASE}/backend/app.pid 2>/dev/null) > /dev/null 2>&1; then
    echo '后端服务启动成功, PID: '\$(cat ${DEPLOY_BASE}/backend/app.pid)
else
    echo '后端服务启动失败'
    tail -20 ${DEPLOY_BASE}/logs/app.log
    exit 1
fi
"@
Invoke-SSH $startScript | ForEach-Object { Log $_ }

Start-Sleep -Seconds 3

Log "执行健康检查..."
$frontendCode = Invoke-SSH "curl -s -o /dev/null -w '%{http_code}' http://localhost:${PORT}/"
$backendCode = Invoke-SSH "curl -s -o /dev/null -w '%{http_code}' http://localhost:${PORT}/api/todos"

$frontendOk = $frontendCode -match "200"
$backendOk = $backendCode -match "200|404"

if ($frontendOk) { Log "✓ 前端页面访问正常" } else { Log "✗ 前端页面访问异常" }
if ($backendOk) { Log "✓ 后端接口访问正常" } else { Log "✗ 后端接口访问异常" }

Log "========================================="
Log "重启完成"
Log "========================================="
