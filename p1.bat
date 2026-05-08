@echo off
setlocal enabledelayedexpansion

set PROJECT_ROOT=%~dp0
if "%PROJECT_ROOT:~-1%"=="\" set PROJECT_ROOT=%PROJECT_ROOT:~0,-1%
set LIB_DIR=%PROJECT_ROOT%\lib
set SRC_DIR=%PROJECT_ROOT%\src\main\java
set BUILD_DIR=%PROJECT_ROOT%\search-engine\WEB-INF\classes
set DB_DIR=%PROJECT_ROOT%\search-engine\WEB-INF\db

set MAIN_CLASS=Phase1Spider
set START_URL=https://www.cse.ust.hk/~kwtleung/COMP4321/testpage.htm
set NUM_PAGES=30
set DB_BASE_PATH=%DB_DIR%\phase1_30
set STOPWORD_PATH=%PROJECT_ROOT%\src\main\resource\stopwords.txt

pushd "%PROJECT_ROOT%"


echo [Step 1] Cleaning search-engine classes directory...
if exist "%BUILD_DIR%" (
    rd /s /q "%BUILD_DIR%"
)
mkdir "%BUILD_DIR%"

echo [Step 2] Ensuring db directory exists...
if not exist "%DB_DIR%" (
    mkdir "%DB_DIR%"
)

echo [Step 3] Finding all source files...
dir /s /b "%SRC_DIR%\*.java" > sources.txt

echo [Step 4] Compiling Java source files...
:: @sources.txt: compile all source files listed in sources.txt
javac -encoding UTF-8 -cp "%LIB_DIR%\*;%BUILD_DIR%" -d "%BUILD_DIR%" @sources.txt

if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Compilation failed!
    del sources.txt
    popd
    pause
    exit /b %ERRORLEVEL%
)
del sources.txt
echo [SUCCESS] Compilation finished.

echo [Step 5] Running %MAIN_CLASS%...
echo ------------------------------------------
java -cp "%BUILD_DIR%;%LIB_DIR%\*" %MAIN_CLASS% "%START_URL%" %NUM_PAGES% "%DB_BASE_PATH%" "%STOPWORD_PATH%"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [TIP] Program exited with error.
    popd
    pause
    exit /b %ERRORLEVEL%
)

echo [SUCCESS] Spider finished. DB files are under %DB_DIR%.

popd

pause