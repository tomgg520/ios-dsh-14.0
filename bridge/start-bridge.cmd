@echo off
chcp 65001 >nul
setlocal
set "HERE=%~dp0"

rem 允许通过环境变量指定 Desktop 的 exe 路径
if defined DSH_EXE (
  set "EXE=%DSH_EXE%"
) else (
  set "EXE=%LOCALAPPDATA%\Programs\DeepSeek Harness\DeepSeek Harness.exe"
)

if not exist "%EXE%" (
  echo.
  echo [DSH Bridge] 没有找到 DeepSeek Harness Desktop。
  echo.
  echo 如果你已经安装 Node.js 20 或更新版本，可以直接运行：
  echo     node "%HERE%server.mjs"
  echo.
  echo 或者先设置环境变量 DSH_EXE 指向 DeepSeek Harness.exe。
  echo.
  pause
  exit /b 1
)

set "ELECTRON_RUN_AS_NODE=1"
"%EXE%" "%HERE%server.mjs"
echo.
echo [DSH Bridge] 桥接服务已退出。
pause
