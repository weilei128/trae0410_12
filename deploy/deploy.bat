@echo off
setlocal enabledelayedexpansion

echo ======================================
echo 博客系统部署脚本 - Windows 入口
echo ======================================

where ssh >nul 2>&1
if %errorlevel% neq 0 (
    echo 错误: 未找到ssh命令，请确保已安装Git Bash或OpenSSH
    echo 请使用 Git Bash 执行 deploy.sh
    pause
    exit /b 1
)

where bash >nul 2>&1
if %errorlevel% equ 0 (
    echo 使用bash执行部署脚本...
    cd /d "%~dp0"
    bash deploy.sh
) else (
    echo 未找到bash，建议使用 Git Bash 执行 deploy.sh
    echo 或者手动在Linux环境下执行
    pause
)

echo.
echo 部署流程结束
pause
