$SERVER = "49.235.161.106"
$SSH_PORT = "22"
$SSH_USER = "root"
$PORT = "10012"
$PROJECT_NAME = "blog"
$DEPLOY_BASE = "/opt/projects/${PROJECT_NAME}_${PORT}"
$BACKUP_BASE = "/opt/backups/${PROJECT_NAME}_${PORT}"
$TIMESTAMP = Get-Date -Format "yyyyMMdd_HHmmss"

function Log([string]$msg) { Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $msg" }
function SSH([string]$cmd) { ssh -p $SSH_PORT "${SSH_USER}@${SERVER}" $cmd 2>&1 }

Log "=== Deploy ${PROJECT_NAME} port:${PORT} ==="

Log "Step 1: Check SSH"
$r = ssh -o ConnectTimeout=5 -p $SSH_PORT "${SSH_USER}@${SERVER}" "echo ok" 2>&1
if ($r -notmatch "ok") { Log "SSH failed"; exit 1 }
Log "SSH OK"

Log "Step 2: Kill port ${PORT}"
SSH "fuser -k ${PORT}/tcp 2>/dev/null; echo done" | Out-Null
Log "Port cleared"

Log "Step 3: Build backend"
Set-Location backend
if (Test-Path "mvnw") { ./mvnw clean package -DskipTests } else { mvn clean package -DskipTests }
Set-Location ..
Log "Backend built"

Log "Step 4: Build frontend"
Set-Location frontend
if (Test-Path "package-lock.json") { npm ci } else { npm install }
npm run build
Set-Location ..
Log "Frontend built"

Log "Step 5: Create directories"
SSH "mkdir -p ${DEPLOY_BASE}/{backend,frontend,logs,nginx} ${BACKUP_BASE}" | Out-Null
Log "Dirs created"

Log "Step 6: Upload JAR"
$jars = Get-ChildItem "backend\target\*.jar" | Where-Object { $_.Name -notmatch "\.original$" }
if ($jars.Count -eq 0) { Log "No JAR"; exit 1 }
$JAR = $jars[0]
SSH "cp ${DEPLOY_BASE}/backend/$($JAR.Name) ${BACKUP_BASE}/$($JAR.Name).${TIMESTAMP} 2>/dev/null" | Out-Null
scp -P $SSH_PORT $JAR.FullName "${SSH_USER}@${SERVER}:${DEPLOY_BASE}/backend/$($JAR.Name)" 2>&1 | Out-Null
Log "JAR uploaded"

Log "Step 7: Upload frontend"
SSH "mv ${DEPLOY_BASE}/frontend/dist ${BACKUP_BASE}/dist.${TIMESTAMP} 2>/dev/null" | Out-Null
scp -P $SSH_PORT -r "frontend\dist" "${SSH_USER}@${SERVER}:${DEPLOY_BASE}/frontend/" 2>&1 | Out-Null
Log "Frontend uploaded"

Log "Step 8: Configure Nginx"
$conf = "server{listen ${PORT};root ${DEPLOY_BASE}/frontend/dist;index index.html;location /{try_files `$uri `$uri/ /index.html;}location /api{proxy_pass http://127.0.0.1:${PORT};proxy_set_header Host `$host;proxy_set_header X-Real-IP `$remote_addr;}location /health{return 200 OK;}}"
SSH "echo '$conf' > ${DEPLOY_BASE}/nginx/app.conf" | Out-Null
SSH "grep -q 'include ${DEPLOY_BASE}/nginx/app.conf' /etc/nginx/nginx.conf || sed -i '/http {/a\    include ${DEPLOY_BASE}/nginx/app.conf;' /etc/nginx/nginx.conf; nginx -t && nginx -s reload 2>/dev/null || nginx; echo nginx_done" | ForEach-Object { Log $_ }

Log "Step 9: Start backend"
SSH "cd ${DEPLOY_BASE}/backend; J=`$(ls *.jar | grep -v original | head -1); nohup java -Xms128m -Xmx256m -jar `$J --server.port=${PORT} > ../logs/app.log 2>&1 & echo `$! > app.pid; sleep 3; ps -p `$(cat app.pid) && echo 'Started PID:' `$(cat app.pid) || (echo 'Failed'; tail -20 ../logs/app.log; exit 1)" | ForEach-Object { Log $_ }

Log "Step 10: Health check"
Start-Sleep 3
$fe = SSH "curl -s -o /dev/null -w '%{http_code}' http://localhost:${PORT}/"
$be = SSH "curl -s -o /dev/null -w '%{http_code}' http://localhost:${PORT}/api/todos"
Log "Frontend: $fe, Backend: $be"

if ($fe -match "200" -and $be -match "200|404") {
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    SSH "echo '{\"project\":\"${PROJECT_NAME}\",\"port\":${PORT},\"time\":\"${time}\"}' > ${DEPLOY_BASE}/deploy_info.json" | Out-Null
    Log "=== DEPLOY SUCCESS ==="
    Log "URL: http://${SERVER}:${PORT}"
} else {
    Log "Health check failed"
    exit 1
}
