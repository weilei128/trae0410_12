param(
    [Parameter(Position=0)]
    [string]$Action = ""
)

$SERVER = "49.235.161.106"
$SSH_PORT = "22"
$SSH_USER = "root"
$PORT = "10012"
$PROJECT_NAME = "blog"
$DEPLOY_BASE = "/opt/projects/${PROJECT_NAME}_${PORT}"
$BACKUP_BASE = "/opt/backups/${PROJECT_NAME}_${PORT}"
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

function Show-Usage {
    Write-Host "用法: .\rollback.ps1 [操作]"
    Write-Host ""
    Write-Host "操作:"
    Write-Host "  list              列出所有可用备份"
    Write-Host "  jar               回滚JAR包到最新备份"
    Write-Host "  frontend          回滚前端到最新备份"
    Write-Host "  all               回滚JAR包和前端到最新备份"
    Write-Host ""
    Write-Host "示例:"
    Write-Host "  .\rollback.ps1 list"
    Write-Host "  .\rollback.ps1 jar"
    Write-Host "  .\rollback.ps1 all"
}

function List-Backups {
    Log "========================================="
    Log "可用的备份列表:"
    Log "========================================="
    
    $script = @"
echo '--- JAR包备份 ---'
ls -lht ${BACKUP_BASE}/*.jar.* 2>/dev/null || echo '无JAR包备份'
echo ''
echo '--- 前端备份 ---'
ls -lht ${BACKUP_BASE}/dist.* 2>/dev/null || echo '无前端备份'
"@
    Invoke-SSH $script
}

function Stop-Backend {
    Log "停止后端服务..."
    $script = @"
if [ -f ${DEPLOY_BASE}/backend/app.pid ]; then
    pid=\$(cat ${DEPLOY_BASE}/backend/app.pid)
    if ps -p \$pid > /dev/null 2>&1; then
        kill -15 \$pid
        sleep 3
        if ps -p \$pid > /dev/null 2>&1; then
            kill -9 \$pid
        fi
        echo '后端服务已停止'
    else
        echo '后端服务未运行'
    fi
else
    echo 'PID文件不存在'
fi
"@
    Invoke-SSH $script | ForEach-Object { Log $_ }
}

function Rollback-Jar {
    Log "回滚JAR包..."
    
    $script = @"
backup_file=\$(ls -t ${BACKUP_BASE}/*.jar.* 2>/dev/null | head -1)

if [ -z \"\$backup_file\" ]; then
    echo '错误: 未找到JAR包备份'
    exit 1
fi

echo \"使用备份: \$backup_file\"
JAR_NAME=\$(basename \"\$backup_file\" | sed 's/\.[0-9_]\+$//')
cp \"\$backup_file\" ${DEPLOY_BASE}/backend/\$JAR_NAME
echo 'JAR包回滚完成'
"@
    Invoke-SSH $script | ForEach-Object { Log $_ }
}

function Rollback-Frontend {
    Log "回滚前端..."
    
    $script = @"
backup_dir=\$(ls -td ${BACKUP_BASE}/dist.* 2>/dev/null | head -1)

if [ -z \"\$backup_dir\" ]; then
    echo '错误: 未找到前端备份'
    exit 1
fi

echo \"使用备份: \$backup_dir\"
rm -rf ${DEPLOY_BASE}/frontend/dist
cp -r \"\$backup_dir\" ${DEPLOY_BASE}/frontend/dist
echo '前端回滚完成'
"@
    Invoke-SSH $script | ForEach-Object { Log $_ }
}

function Start-Backend {
    Log "启动后端服务..."
    
    $script = @"
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
    exit 1
fi
"@
    Invoke-SSH $script | ForEach-Object { Log $_ }
}

function Reload-Nginx {
    Log "重载Nginx配置..."
    Invoke-SSH "nginx -t && nginx -s reload 2>/dev/null || nginx" | ForEach-Object { Log $_ }
}

function Test-Health {
    Log "执行健康检查..."
    Start-Sleep -Seconds 3
    
    $frontendCode = Invoke-SSH "curl -s -o /dev/null -w '%{http_code}' http://localhost:${PORT}/"
    $backendCode = Invoke-SSH "curl -s -o /dev/null -w '%{http_code}' http://localhost:${PORT}/api/todos"
    
    $frontendOk = $frontendCode -match "200"
    $backendOk = $backendCode -match "200|404"
    
    if ($frontendOk) { Log "✓ 前端页面访问正常" } else { Log "✗ 前端页面访问异常" }
    if ($backendOk) { Log "✓ 后端接口访问正常" } else { Log "✗ 后端接口访问异常" }
    
    return ($frontendOk -and $backendOk)
}

Log "========================================="
Log "开始回滚 ${PROJECT_NAME} 端口: ${PORT}"
Log "========================================="

switch ($Action) {
    "list" {
        List-Backups
    }
    "jar" {
        Stop-Backend
        Rollback-Jar
        Start-Backend
        if (Test-Health) {
            Log "回滚成功"
        }
    }
    "frontend" {
        Rollback-Frontend
        Reload-Nginx
        if (Test-Health) {
            Log "回滚成功"
        }
    }
    "all" {
        Stop-Backend
        Rollback-Jar
        Rollback-Frontend
        Start-Backend
        Reload-Nginx
        if (Test-Health) {
            Log "回滚成功"
        }
    }
    default {
        Show-Usage
    }
}

Log "========================================="
Log "回滚操作完成"
Log "========================================="
