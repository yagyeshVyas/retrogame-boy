@echo off
set "PATH=C:\Users\yagyesh\flutter-sdk\flutter\bin;C:\Program Files\Git\cmd;C:\Program Files\Git\bin;C:\Windows\System32;C:\Windows\System32\WindowsPowerShell\v1.0;%PATH%"
cd /d C:\Users\yagyesh\RetroLAN-console\controller-app
echo --- PUB GET ---
call flutter pub get
echo --- ANALYZE ---
call flutter analyze
