# ============================================
# PowerShell部署脚本 - 端口10013实例专用
# ============================================

$ErrorActionPreference = "Stop"

# 配置
$SERVER_HOST = "49.235.161.106"
$SERVER_USER = "root"
$APP_PORT = 10013

# 本地路径
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$PROJECT_ROOT = Split-Path -Parent $SCRIPT_DIR
$REMOTE_BASE_DIR = "/opt/blog-app/${APP_PORT}"
$REMOTE_SOURCE_DIR = "${REMOTE_BASE_DIR}/source"

# 输出函数
function Write-Info($msg) {
    Write-Host "[INFO] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $msg" -ForegroundColor Cyan
}

function Write-Success($msg) {
    Write-Host "[SUCCESS] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $msg" -ForegroundColor Green
}

function Write-Warn($msg) {
    Write-Host "[WARN] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $msg" -ForegroundColor Yellow
}

function Write-ErrorLog($msg) {
    Write-Host "[ERROR] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $msg" -ForegroundColor Red
}

# 检查SSH连接
function Test-SshConnection {
    Write-Info "检查SSH连接..."
    try {
        $result = ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${SERVER_USER}@${SERVER_HOST}" "echo 'SSH_OK'" 2>&1
        if ($result -eq "SSH_OK") {
            Write-Success "SSH连接正常"
            return $true
        }
    } catch {
        Write-ErrorLog "SSH连接失败: $_"
    }
    return $false
}

# 上传源代码
function Upload-SourceCode {
    Write-Info "上传源代码到服务器..."
    
    # 创建远程目录
    ssh "${SERVER_USER}@${SERVER_HOST}" "mkdir -p ${REMOTE_SOURCE_DIR}"
    
    # 上传后端代码
    Write-Info "上传后端代码..."
    $backendSrc = Join-Path $PROJECT_ROOT "backend"
    scp -r "${backendSrc}\*" "${SERVER_USER}@${SERVER_HOST}:${REMOTE_SOURCE_DIR}/backend/"
    
    # 上传前端代码
    Write-Info "上传前端代码..."
    $frontendSrc = Join-Path $PROJECT_ROOT "frontend"
    scp -r "${frontendSrc}\*" "${SERVER_USER}@${SERVER_HOST}:${REMOTE_SOURCE_DIR}/frontend/"
    
    # 上传远程部署脚本
    Write-Info "上传部署脚本..."
    $deployScript = Join-Path $SCRIPT_DIR "remote-deploy.sh"
    scp $deployScript "${SERVER_USER}@${SERVER_HOST}:${REMOTE_BASE_DIR}/"
    
    Write-Success "代码上传完成"
}

# 执行远程部署
function Invoke-RemoteDeploy {
    Write-Info "在服务器上执行部署..."
    ssh "${SERVER_USER}@${SERVER_HOST}" "cd ${REMOTE_BASE_DIR} && bash remote-deploy.sh deploy"
}

# 执行远程命令
function Invoke-RemoteCommand($command) {
    ssh "${SERVER_USER}@${SERVER_HOST}" "cd ${REMOTE_BASE_DIR} && bash remote-deploy.sh ${command}"
}

# 完整部署
function Start-FullDeploy {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host "  博客项目部署 - 端口 ${APP_PORT} 实例" -ForegroundColor Blue
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host ""
    
    if (-not (Test-SshConnection)) {
        Write-ErrorLog "SSH连接失败，请检查密钥配置"
        exit 1
    }
    
    Upload-SourceCode
    Invoke-RemoteDeploy
    
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Green
    Write-Success "本地部署流程完成"
    Write-Host "==========================================" -ForegroundColor Green
}

# 显示帮助
function Show-Help {
    Write-Host ""
    Write-Host "博客项目部署脚本 - 端口10013实例"
    Write-Host ""
    Write-Host "用法: .\deploy.ps1 [命令]"
    Write-Host ""
    Write-Host "部署命令:"
    Write-Host "  deploy     完整部署（上传代码+构建+部署）"
    Write-Host ""
    Write-Host "远程运维命令:"
    Write-Host "  restart    一键重启"
    Write-Host "  stop       停止服务"
    Write-Host "  start      启动服务"
    Write-Host "  status     查看状态"
    Write-Host "  rollback   回滚到上一个版本"
    Write-Host "  health     健康检查"
    Write-Host ""
}

# 主逻辑
$command = $args[0]

if ($command -eq "deploy") {
    Start-FullDeploy
}
elseif ($command -eq "restart") {
    if (Test-SshConnection) { Invoke-RemoteCommand "restart" }
}
elseif ($command -eq "stop") {
    if (Test-SshConnection) { Invoke-RemoteCommand "stop" }
}
elseif ($command -eq "start") {
    if (Test-SshConnection) { Invoke-RemoteCommand "start" }
}
elseif ($command -eq "status") {
    if (Test-SshConnection) { Invoke-RemoteCommand "status" }
}
elseif ($command -eq "rollback") {
    if (Test-SshConnection) { Invoke-RemoteCommand "rollback" }
}
elseif ($command -eq "health") {
    if (Test-SshConnection) { Invoke-RemoteCommand "health" }
}
else {
    Show-Help
}
