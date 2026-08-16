@echo off
set "PATH=C:\Users\yagyesh\flutter-sdk\flutter\bin;C:\Program Files\Git\cmd;C:\Program Files\Git\bin;C:\Windows\System32;C:\Windows\System32\WindowsPowerShell\v1.0;%PATH%"
cd /d C:\Users\yagyesh\RetroLAN-console\controller-app
echo --- ANALYZE ---
call flutter analyze
echo --- BUILD PHONE APK ---
call flutter build apk --release
echo DONE_%ERRORLEVEL%
