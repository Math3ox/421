@echo off
rem Compile 421.s (+ render.s, game.s, term.s, ai.s) en 421.exe avec le gcc/as/ld de MSYS2 (ucrt64)
set PATH=C:\msys64\ucrt64\bin;%PATH%
gcc -nostartfiles -nostdlib -mwindows -o 421.exe 421.s -lkernel32 -luser32 -lgdi32 -Wl,-e,start
if errorlevel 1 (echo ECHEC) else (echo OK)
