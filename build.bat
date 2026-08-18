@echo off
setlocal EnableExtensions EnableDelayedExpansion

echo ========================================
echo  Windows CUDA Build (Native x64 Mode)
echo ========================================
echo.

set "NVCC=nvcc"
set "OUTDIR=build-windows"
set "OUT=%OUTDIR%\texture-search.exe"

REM ============================================================
REM Force the Native x64 Visual Studio Compiler Environment
REM ============================================================
if exist "%ProgramFiles%\Microsoft Visual Studio\Installer\vswhere.exe" (
    for /f "usebackq delims=" %%i in (`
        "%ProgramFiles%\Microsoft Visual Studio\Installer\vswhere.exe" ^
        -latest ^
        -products * ^
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 ^
        -property installationPath
    `) do (
        set "VSINSTALL=%%i"
    )
)

if defined VSINSTALL (
    echo Loading Native 64-bit Visual Studio environment variables...
    call "!VSINSTALL!\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
)

where cl.exe | findstr /i "Hostx64\x64" >nul 2>&1
if errorlevel 1 (
    echo.
    echo WARNING: Native x64 toolchain not active. Forcing explicit path override...
    for /d %%D in ("%ProgramFiles%\Microsoft Visual Studio\2026\Community\VC\Tools\MSVC\*") do (
        if exist "%%D\bin\Hostx64\x64\cl.exe" (
            set "PATH=%%D\bin\Hostx64\x64;!PATH!"
        )
    )
)

echo Using Compiler Host:
where cl.exe
echo.

REM ============================================================
REM Set Safe Unified CUDA Architecture for RTX 4070 Ti
REM ============================================================
set "ARCHFLAGS=-arch=native"

REM ============================================================
REM Build Execution
REM ============================================================
if not exist "%OUTDIR%" (
    mkdir "%OUTDIR%"
)

echo ========================================
echo  Compiling
echo ========================================
echo.

"%NVCC%" ^
    -std=c++17 ^
    -O3 ^
    --use_fast_math ^
    %ARCHFLAGS% ^
    -Iinclude ^
    src\main.cu ^
    src\texture_search.cu ^
    -o "%OUT%"

if errorlevel 1 (
    echo.
    echo ========================================
    echo  BUILD FAILED
    echo ========================================
    echo.
    pause
    exit /b 1
)

echo.
echo ========================================
echo  BUILD SUCCESSFUL
echo ========================================
echo.
echo Executable saved to:
echo   %OUT%
echo.

endlocal
pause
