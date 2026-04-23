$PROJECT_PORT = "10011"
$BACKEND_PORT = "100110"
$SERVER_IP = "49.235.161.106"
$SERVER_USER = "root"
$SSH_PORT = "22"
$BASE_DIR = "/opt/blog-instance-${PROJECT_PORT}"
$JAR_NAME = "todo-app.jar"

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "博客系统部署脚本 - PowerShell 版本" -ForegroundColor Cyan
Write-Host "实例端口: ${PROJECT_PORT}" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan

$DEPLOY_START_TIME = Get-Date
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$PROJECT_ROOT = Split-Path -Parent $SCRIPT_DIR

function Execute-SSH {
    param([string]$Command)
    ssh -p $SSH_PORT "${SERVER_USER}@${SERVER_IP}" $Command
}

Write-Host "[1/8] 初始化服务器目录结构..." -ForegroundColor Yellow
Execute-SSH @"
mkdir -p ${BASE_DIR}/backend
mkdir -p ${BASE_DIR}/frontend/dist
mkdir -p ${BASE_DIR}/logs
mkdir -p ${BASE_DIR}/nginx
mkdir -p ${BASE_DIR}/backup
mkdir -p ${BASE_DIR}/script
echo "目录创建完成: ${BASE_DIR}"
ls -la ${BASE_DIR}
"@

Write-Host "[2/8] 安全查杀端口 ${PROJECT_PORT} 和 ${BACKEND_PORT} 进程..." -ForegroundColor Yellow
Execute-SSH @"
PORT1=${PROJECT_PORT}
PORT2=${BACKEND_PORT}
echo "检查端口 \${PORT1} 和 \${PORT2} ..."
for PORT in \${PORT1} \${PORT2}; do
    PIDS=\$(lsof -ti:\${PORT} 2>/dev/null || echo "")
    if [ -n "\${PIDS}" ]; then
        echo "端口 \${PORT}: 发现进程 \${PIDS}, 正在终止..."
        kill -15 \${PIDS} 2>/dev/null || true
        sleep 1
        kill -9 \${PIDS} 2>/dev/null || true
    fi
done
echo "端口清理完成"
"@

Write-Host "[3/8] 准备后端jar包..." -ForegroundColor Yellow
$JAR_SOURCE = Get-ChildItem -Path "${PROJECT_ROOT}\backend\target" -Filter "*.jar" -File | 
              Where-Object { $_.Name -notlike "*original*" } | 
              Select-Object -First 1 -ExpandProperty FullName

if (-not $JAR_SOURCE) {
    Write-Host "未找到jar包，正在编译后端..." -ForegroundColor Red
    Set-Location "${PROJECT_ROOT}\backend"
    if (Get-Command mvn -ErrorAction SilentlyContinue) {
        mvn clean package -DskipTests
    } else {
        Write-Host "Maven未找到，使用现有jar包..." -ForegroundColor Yellow
    }
    $JAR_SOURCE = Get-ChildItem -Path "${PROJECT_ROOT}\backend\target" -Filter "*.jar" -File | 
                  Where-Object { $_.Name -notlike "*original*" } | 
                  Select-Object -First 1 -ExpandProperty FullName
}
Write-Host "使用jar包: $JAR_SOURCE" -ForegroundColor Green

Write-Host "[4/8] 上传并部署后端服务..." -ForegroundColor Yellow
$BACKUP_TIME = Get-Date -Format "yyyyMMdd_HHmmss"
Execute-SSH @"
if [ -f "${BASE_DIR}/backend/${JAR_NAME}" ]; then
    cp "${BASE_DIR}/backend/${JAR_NAME}" "${BASE_DIR}/backup/${JAR_NAME}.${BACKUP_TIME}"
    echo "已备份当前版本"
fi
"@

scp -P $SSH_PORT $JAR_SOURCE "${SERVER_USER}@${SERVER_IP}:${BASE_DIR}/backend/${JAR_NAME}"

Write-Host "[5/8] 启动后端服务..." -ForegroundColor Yellow
Execute-SSH @"
if ! command -v java &> /dev/null; then
    echo "安装Java..."
    apt-get update && apt-get install -y openjdk-11-jre-headless || yum install -y java-11-openjdk-headless
fi

PID_FILE="${BASE_DIR}/backend/app.pid"
if [ -f "\${PID_FILE}" ]; then
    PID=\$(cat "\${PID_FILE}")
    kill -9 \${PID} 2>/dev/null || true
    rm -f "\${PID_FILE}"
fi

cd ${BASE_DIR}/backend
nohup java -jar -Dserver.port=${BACKEND_PORT} ${JAR_NAME} > ${BASE_DIR}/logs/backend.log 2>&1 &
echo \$! > ${BASE_DIR}/backend/app.pid
echo "后端服务已启动, PID: \$!"
sleep 5
ps aux | grep java | grep -v grep
"@

Write-Host "[6/8] 部署前端文件..." -ForegroundColor Yellow
if (Test-Path "${PROJECT_ROOT}\frontend\dist") {
    Write-Host "打包前端文件..." -ForegroundColor Yellow
    Set-Location "${PROJECT_ROOT}\frontend"
    tar -czf "$env:TEMP\frontend-dist.tar.gz" dist
    scp -P $SSH_PORT "$env:TEMP\frontend-dist.tar.gz" "${SERVER_USER}@${SERVER_IP}:${BASE_DIR}/frontend/"
    Execute-SSH @"
cd ${BASE_DIR}/frontend
rm -rf dist
tar -xzf frontend-dist.tar.gz
rm -f frontend-dist.tar.gz
echo "前端文件已部署"
ls -la dist/
"@
} else {
    Write-Host "前端dist目录不存在，跳过..." -ForegroundColor Yellow
}

Write-Host "[7/8] 配置Nginx..." -ForegroundColor Yellow
Execute-SSH @"
if ! command -v nginx &> /dev/null; then
    echo "安装Nginx..."
    apt-get update && apt-get install -y nginx || yum install -y nginx
fi

mkdir -p /etc/nginx/conf.d/

cat > /etc/nginx/conf.d/blog-${PROJECT_PORT}.conf << 'NGINXCONF'
server {
    listen ${PROJECT_PORT};
    server_name _;

    root ${BASE_DIR}/frontend/dist;
    index index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:${BACKEND_PORT}/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
NGINXCONF

nginx -t && systemctl restart nginx || echo "Nginx配置完成"
"@

Write-Host "[8/8] 执行健康检查..." -ForegroundColor Yellow
Start-Sleep -Seconds 8

Write-Host "`n检查后端接口..." -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "http://${SERVER_IP}:${PROJECT_PORT}/api/todo" -TimeoutSec 10 -UseBasicParsing
    Write-Host "✅ 后端接口正常: HTTP $($response.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "⚠️  后端接口状态: $_" -ForegroundColor Yellow
}

Write-Host "`n检查前端页面..." -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "http://${SERVER_IP}:${PROJECT_PORT}/" -TimeoutSec 10 -UseBasicParsing
    Write-Host "✅ 前端页面正常: HTTP $($response.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "⚠️  前端页面状态: $_" -ForegroundColor Yellow
}

$DEPLOY_END_TIME = Get-Date
$DEPLOY_DURATION = ($DEPLOY_END_TIME - $DEPLOY_START_TIME).TotalSeconds.ToString("0")

Write-Host "`n======================================" -ForegroundColor Green
Write-Host "部署完成! 耗时: ${DEPLOY_DURATION} 秒" -ForegroundColor Green
Write-Host "前端访问: http://${SERVER_IP}:${PROJECT_PORT}" -ForegroundColor Green
Write-Host "后端接口: http://${SERVER_IP}:${PROJECT_PORT}/api/todo" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green
