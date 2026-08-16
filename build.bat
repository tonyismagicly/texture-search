@echo off
setlocal EnableExtensions EnableDelayedExpansion

echo ========================================
echo  Windows CUDA build
echo ========================================
echo.

set "NVCC=nvcc"
set "OUTDIR=build-windows"
set "OUT=%OUTDIR%\texture-search.exe"

REM ============================================================
REM Find nvcc
REM ============================================================

where "%NVCC%" >nul 2>&1

if errorlevel 1 (
    echo ERROR: nvcc was not found in PATH.
    echo.
    echo Install the CUDA Toolkit and make sure nvcc is available.
    pause
    exit /b 1
)

echo Using nvcc:
where "%NVCC%"
echo.

"%NVCC%" --version
if errorlevel 1 (
    echo ERROR: Could not run nvcc.
    pause
    exit /b 1
)

echo.

REM ============================================================
REM Check source files
REM ============================================================

if not exist "src\main.cu" (
    echo ERROR: src\main.cu not found.
    pause
    exit /b 1
)

if not exist "src\texture_search.cu" (
    echo ERROR: src\texture_search.cu not found.
    pause
    exit /b 1
)

if not exist "include\texture_search.cuh" (
    echo ERROR: include\texture_search.cuh not found.
    pause
    exit /b 1
)

REM ============================================================
REM Find MSVC
REM ============================================================

where cl.exe >nul 2>&1

if errorlevel 1 (

    echo cl.exe not found in PATH.
    echo Attempting to locate Visual Studio...
    echo.

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
        echo Visual Studio:
        echo   !VSINSTALL!
        echo.

        call "!VSINSTALL!\VC\Auxiliary\Build\vcvars64.bat"

        if errorlevel 1 (
            echo ERROR: Failed to initialize MSVC.
            pause
            exit /b 1
        )
    )
)

where cl.exe >nul 2>&1

if errorlevel 1 (
    echo.
    echo ERROR: MSVC cl.exe could not be found.
    echo.
    echo Install Visual Studio 2022 with:
    echo   Desktop development with C++
    echo.
    pause
    exit /b 1
)

echo Using MSVC:
where cl.exe
echo.

REM ============================================================
REM Detect CUDA architectures supported by THIS nvcc
REM ============================================================

echo ========================================
echo  Detecting CUDA architectures
echo ========================================
echo.

set "ARCHFLAGS="

for /f "tokens=1" %%A in ('"%NVCC%" --list-gpu-code 2^>nul') do (

    set "CODE=%%A"

    REM Only accept real sm_XX architectures.
    echo !CODE! | findstr /r "^sm_[0-9][0-9]*$" >nul

    if not errorlevel 1 (
        echo Detected: !CODE!
        set "ARCHFLAGS=!ARCHFLAGS! -gencode=arch=compute_!CODE:~3!,code=!CODE!"
    )
)

if not defined ARCHFLAGS (
    echo.
    echo ERROR: Could not determine CUDA architectures.
    echo.
    echo Try:
    echo   nvcc --list-gpu-code
    echo.
    pause
    exit /b 1
)

echo.
echo CUDA architecture flags:
echo !ARCHFLAGS!
echo.

REM ============================================================
REM Add PTX for the highest architecture
REM ============================================================

set "HIGHEST="

for /f "tokens=1" %%A in ('"%NVCC%" --list-gpu-code 2^>nul') do (

    set "CODE=%%A"

    echo !CODE! | findstr /r "^sm_[0-9][0-9]*$" >nul

    if not errorlevel 1 (
        set "HIGHEST=!CODE!"
    )
)

if defined HIGHEST (

    set "COMPUTE=!HIGHEST:sm_=compute_!"

    echo Highest architecture:
    echo   !HIGHEST!
    echo.
    echo Adding PTX fallback:
    echo   !COMPUTE!
    echo.

    set "ARCHFLAGS=!ARCHFLAGS! -gencode=arch=!COMPUTE!,code=!COMPUTE!"
)

REM ============================================================
REM Build
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
    !ARCHFLAGS! ^
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
echo Executable:
echo   %OUT%
echo.

endlocal
pause
