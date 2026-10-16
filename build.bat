@echo off
set PATH=C:\msys64\ucrt64\bin;%PATH%
gcc -nostartfiles -nostdlib -mwindows -o 421.exe 421.s -lkernel32 -luser32 -lgdi32 -Wl,-e,start
if errorlevel 1 (echo ECHEC) else (echo OK)
