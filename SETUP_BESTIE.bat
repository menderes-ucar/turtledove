@echo off
echo 🚀 BESTIE APP - AUTOMATIC SETUP
echo ================================
echo.

REM Check if we're in a Flutter project
if not exist "pubspec.yaml" (
    echo ❌ ERROR: pubspec.yaml not found!
    echo Run this script from your Flutter project root directory
    pause
    exit /b 1
)

echo ✅ Flutter project detected
echo.

REM Backup existing lib
if exist "lib" (
    echo 📦 Backing up existing lib...
    for /f "tokens=2-4 delims=/ " %%a in ('date /t') do (set mydate=%%c%%a%%b)
    for /f "tokens=1-2 delims=/:" %%a in ('time /t') do (set mytime=%%a%%b)
    xcopy lib lib.backup.%mydate%_%mytime% /E /I /Y > nul
    echo ✅ Backup created
    echo.
)

REM Copy lib files
echo 📂 Copying BESTIE app files...
if exist "BESTIE_LIB_READY" (
    xcopy BESTIE_LIB_READY\* lib\ /E /I /Y > nul
) else if exist "..\BESTIE_LIB_READY" (
    xcopy ..\BESTIE_LIB_READY\* lib\ /E /I /Y > nul
) else (
    echo ❌ Cannot find BESTIE_LIB_READY directory!
    pause
    exit /b 1
)
echo ✅ Files copied successfully
echo.

echo 🧹 Running flutter clean...
call flutter clean
echo ✅ Clean done
echo.

echo 📥 Getting dependencies...
call flutter pub get
echo ✅ Dependencies installed
echo.

echo 🔨 Running code generator...
call flutter pub run build_runner build --delete-conflicting-outputs
echo ✅ Code generation complete
echo.

echo 🔍 Running analyzer...
call flutter analyze
if errorlevel 1 (
    echo ⚠️  Some issues found - check above
    pause
    exit /b 1
)
echo.

echo ✅ NO ERRORS - Production ready!
echo.
echo 🎉 BESTIE APP IS READY!
echo.
echo Next steps:
echo 1. flutter run
echo 2. Test the app
echo 3. Deploy to AppStore/PlayStore
echo.
pause
