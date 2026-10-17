@echo off
rem Build de TEST (touches T et B actives) : utilis? par bench.py, bottest.py... Ne pas distribuer.
set PATH=C:\msys64\ucrt64\bin;%PATH%
gcc -nostartfiles -nostdlib -mwindows -o 421.exe 421.s -lkernel32 -luser32 -lgdi32 -Wl,-e,start -Wa,--defsym,DEVTOOLS=1
if errorlevel 1 (echo ECHEC) else (echo OK)
