@echo off
REM ============================================================
REM  Snap3D — Blender Headless Optimizer Runner (Windows)
REM ============================================================
REM  Kullanim:
REM    run_blender.bat --input model.obj --output output.glb
REM    run_blender.bat --input model.obj --output output.glb --decimate 0.05
REM ============================================================

setlocal enabledelayedexpansion

REM ─── Blender yolunu bul ────────────────────────────────────
REM  Önce mevcut PATH'e bak
where blender >nul 2>&1
if %ERRORLEVEL% == 0 (
    set "BLENDER_EXE=blender"
    goto :found
)

REM  Yaygın kurulum yollarını dene
set "BLENDER_PATHS[0]=C:\Program Files\Blender Foundation\Blender 4.3\blender.exe"
set "BLENDER_PATHS[1]=C:\Program Files\Blender Foundation\Blender 4.2\blender.exe"
set "BLENDER_PATHS[2]=C:\Program Files\Blender Foundation\Blender 4.1\blender.exe"
set "BLENDER_PATHS[3]=C:\Program Files\Blender Foundation\Blender 4.0\blender.exe"
set "BLENDER_PATHS[4]=C:\Program Files\Blender Foundation\Blender 3.6\blender.exe"
set "BLENDER_PATHS[5]=C:\Program Files\Blender Foundation\Blender 3.5\blender.exe"

for /L %%i in (0,1,5) do (
    if exist "!BLENDER_PATHS[%%i]!" (
        set "BLENDER_EXE=!BLENDER_PATHS[%%i]!"
        goto :found
    )
)

echo [HATA] Blender bulunamadi!
echo Lutfen Blender'i kurun: https://www.blender.org/download/
echo Ya da BLENDER_EXE ortam degiskenini ayarlayin:
echo   set BLENDER_EXE=C:\path\to\blender.exe
exit /b 1

:found
echo [Snap3D] Blender bulundu: %BLENDER_EXE%

REM ─── Script yolunu belirle ──────────────────────────────────
set "SCRIPT_DIR=%~dp0"
set "OPTIMIZER_SCRIPT=%SCRIPT_DIR%blender_optimizer.py"

if not exist "%OPTIMIZER_SCRIPT%" (
    echo [HATA] blender_optimizer.py bulunamadi: %OPTIMIZER_SCRIPT%
    exit /b 1
)

REM ─── Argümanları geçir ────────────────────────────────────—
echo [Snap3D] Pipeline baslatiliyor...
echo [Snap3D] Script   : %OPTIMIZER_SCRIPT%
echo [Snap3D] Argümanlar: %*
echo.

"%BLENDER_EXE%" --background --python "%OPTIMIZER_SCRIPT%" -- %*

if %ERRORLEVEL% == 0 (
    echo.
    echo [Snap3D] ================================================
    echo [Snap3D] Pipeline BASARIYLA tamamlandi!
    echo [Snap3D] ================================================
) else (
    echo.
    echo [HATA] Pipeline basarisiz oldu. Yukaridaki loglari inceleyin.
    exit /b 1
)

endlocal
