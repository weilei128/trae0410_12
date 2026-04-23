param(
    [string]$Type = "app",
    [int]$Lines = 50
)

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

function Show-Usage {
    Write-Host "用法: .\logs.ps1 [-Type 类型] [-Lines 行数]"
    Write-Host ""
    Write-Host "类型:"
    Write-Host "  app      查看后端应用日志(默认)"
    Write-Host "  nginx    查看Nginx访问日志"
    Write-Host "  error    查看Nginx错误日志"
    Write-Host "  deploy   查看部署日志"
    Write-Host "  all      查看所有日志概览"
    Write-Host ""
    Write-Host "示例:"
    Write-Host "  .\logs.ps1 -Type app -Lines 100"
    Write-Host "  .\logs.ps1 nginx"
}

switch ($Type) {
    "app" {
        Write-Host "========================================="
        Write-Host "后端应用日志 (最近 $Lines 行)"
        Write-Host "========================================="
        Invoke-SSH "tail -n $Lines ${DEPLOY_BASE}/logs/app.log 2>/dev/null || echo '日志文件不存在'"
    }
    "nginx" {
        Write-Host "========================================="
        Write-Host "Nginx访问日志 (最近 $Lines 行)"
        Write-Host "========================================="
        Invoke-SSH "tail -n $Lines ${DEPLOY_BASE}/logs/nginx_access.log 2>/dev/null || echo '日志文件不存在'"
    }
    "error" {
        Write-Host "========================================="
        Write-Host "Nginx错误日志 (最近 $Lines 行)"
        Write-Host "========================================="
        Invoke-SSH "tail -n $Lines ${DEPLOY_BASE}/logs/nginx_error.log 2>/dev/null || echo '日志文件不存在'"
    }
    "deploy" {
        Write-Host "========================================="
        Write-Host "部署日志 (最近 $Lines 行)"
        Write-Host "========================================="
        Invoke-SSH "tail -n $Lines /opt/deploy_logs/${PROJECT_NAME}_${PORT}.log 2>/dev/null || echo '日志文件不存在'"
    }
    "all" {
        Write-Host "========================================="
        Write-Host "所有日志概览"
        Write-Host "========================================="
        Write-Host ""
        Write-Host "--- 后端应用日志 ---"
        Invoke-SSH "tail -n 10 ${DEPLOY_BASE}/logs/app.log 2>/dev/null || echo '无'"
        Write-Host ""
        Write-Host "--- Nginx访问日志 ---"
        Invoke-SSH "tail -n 5 ${DEPLOY_BASE}/logs/nginx_access.log 2>/dev/null || echo '无'"
        Write-Host ""
        Write-Host "--- Nginx错误日志 ---"
        Invoke-SSH "tail -n 5 ${DEPLOY_BASE}/logs/nginx_error.log 2>/dev/null || echo '无'"
        Write-Host ""
        Write-Host "--- 部署日志 ---"
        Invoke-SSH "tail -n 5 /opt/deploy_logs/${PROJECT_NAME}_${PORT}.log 2>/dev/null || echo '无'"
    }
    "help" {
        Show-Usage
    }
    default {
        Show-Usage
    }
}
