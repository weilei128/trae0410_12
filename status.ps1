$SERVER = "49.235.161.106"
$SSH_PORT = "22"
$SSH_USER = "root"
$PORT = "10012"
$PROJECT_NAME = "blog"
$DEPLOY_BASE = "/opt/projects/${PROJECT_NAME}_${PORT}"

function Invoke-SSH {
    param([string]$command)
    $result = ssh -p $SSH_PORT "${SSH_USER}@${SERVER}" $command 2>&1
    return $result
}

Write-Host "========================================="
Write-Host "服务状态检查 ${PROJECT_NAME} 端口: ${PORT}"
Write-Host "========================================="

Write-Host ""
Write-Host "========================================="
Write-Host "进程状态"
Write-Host "========================================="

$processScript = @"
if [ -f ${DEPLOY_BASE}/backend/app.pid ]; then
    pid=\$(cat ${DEPLOY_BASE}/backend/app.pid)
    if ps -p \$pid > /dev/null 2>&1; then
        echo '✓ 后端服务运行中 (PID: '\$pid')'
        ps -p \$pid -o pid,ppid,%cpu,%mem,etime,args --no-headers
    else
        echo '✗ 后端服务未运行 (PID文件存在但进程不存在)'
    fi
else
    echo '✗ 后端服务未运行 (无PID文件)'
fi

echo ''
echo '端口 ${PORT} 监听状态:'
netstat -tlnp 2>/dev/null | grep ':${PORT} ' || echo '端口 ${PORT} 未被监听'
"@
Invoke-SSH $processScript

Write-Host ""
Write-Host "========================================="
Write-Host "健康检查"
Write-Host "========================================="

$healthScript = @"
echo '--- 前端页面 ---'
http_code=\$(curl -s -o /dev/null -w '%{http_code}' http://localhost:${PORT}/ 2>/dev/null)
if [ \"\$http_code\" = \"200\" ]; then
    echo '✓ 前端页面正常 (HTTP '\$http_code')'
else
    echo '✗ 前端页面异常 (HTTP '\$http_code')'
fi

echo ''
echo '--- 后端接口 ---'
http_code=\$(curl -s -o /dev/null -w '%{http_code}' http://localhost:${PORT}/api/todos 2>/dev/null)
if [ \"\$http_code\" = \"200\" ] || [ \"\$http_code\" = \"404\" ]; then
    echo '✓ 后端接口正常 (HTTP '\$http_code')'
else
    echo '✗ 后端接口异常 (HTTP '\$http_code')'
fi

echo ''
echo '--- 外部访问 ---'
http_code=\$(curl -s -o /dev/null -w '%{http_code}' http://${SERVER}:${PORT}/ 2>/dev/null)
if [ \"\$http_code\" = \"200\" ]; then
    echo '✓ 外部访问正常 (HTTP '\$http_code')'
else
    echo '✗ 外部访问异常 (HTTP '\$http_code')'
fi
"@
Invoke-SSH $healthScript

Write-Host ""
Write-Host "========================================="
Write-Host "文件状态"
Write-Host "========================================="

$fileScript = @"
echo '--- 后端文件 ---'
if ls ${DEPLOY_BASE}/backend/*.jar >/dev/null 2>&1; then
    ls -lh ${DEPLOY_BASE}/backend/*.jar | grep -v '\.original'
else
    echo '无JAR包'
fi

echo ''
echo '--- 前端文件 ---'
if [ -d ${DEPLOY_BASE}/frontend/dist ]; then
    file_count=\$(find ${DEPLOY_BASE}/frontend/dist -type f | wc -l)
    echo '✓ 前端dist目录存在 ('\$file_count' 个文件)'
else
    echo '✗ 前端dist目录不存在'
fi

echo ''
echo '--- 日志文件 ---'
ls -lh ${DEPLOY_BASE}/logs/*.log 2>/dev/null || echo '无日志文件'

echo ''
echo '--- Nginx配置 ---'
if [ -f ${DEPLOY_BASE}/nginx/app.conf ]; then
    echo '✓ Nginx配置文件存在'
else
    echo '✗ Nginx配置文件不存在'
fi
"@
Invoke-SSH $fileScript

Write-Host ""
Write-Host "========================================="
Write-Host "部署信息"
Write-Host "========================================="

$deployInfoScript = "if [ -f ${DEPLOY_BASE}/deploy_info.json ]; then cat ${DEPLOY_BASE}/deploy_info.json; else echo '无部署信息文件'; fi"
Invoke-SSH $deployInfoScript

Write-Host ""
Write-Host "========================================="
Write-Host "资源使用"
Write-Host "========================================="

$resourceScript = @"
echo '--- 磁盘使用 ---'
df -h ${DEPLOY_BASE} 2>/dev/null || df -h /opt

echo ''
echo '--- 项目目录大小 ---'
du -sh ${DEPLOY_BASE} 2>/dev/null || echo '目录不存在'

echo ''
echo '--- 备份目录大小 ---'
du -sh /opt/backups/${PROJECT_NAME}_${PORT} 2>/dev/null || echo '备份目录不存在'
"@
Invoke-SSH $resourceScript

Write-Host ""
Write-Host "========================================="
Write-Host "检查完成"
Write-Host "========================================="
