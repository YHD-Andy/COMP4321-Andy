#!/usr/bin/env bash

set -u

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"
SRC_DIR="$PROJECT_ROOT/src/main/java"
BUILD_DIR="$PROJECT_ROOT/search-engine/WEB-INF/classes"
DB_DIR="$PROJECT_ROOT/search-engine/WEB-INF/db"

MAIN_CLASS="Phase1Spider"
START_URL="https://www.cse.ust.hk/~kwtleung/COMP4321/testpage.htm"
NUM_PAGES="30"
DB_BASE_PATH="$DB_DIR/phase1_30"
STOPWORD_PATH="$PROJECT_ROOT/src/main/resource/stopwords.txt"

cd "$PROJECT_ROOT" || exit 1

echo "[Step 1] Cleaning search-engine classes directory..."
if [ -d "$BUILD_DIR" ]; then
    rm -rf "$BUILD_DIR"
fi
mkdir -p "$BUILD_DIR"

echo "[Step 2] Ensuring db directory exists..."
mkdir -p "$DB_DIR"

echo "[Step 3] Finding all source files..."
SOURCE_LIST="$PROJECT_ROOT/sources.txt"
find "$SRC_DIR" -type f -name "*.java" > "$SOURCE_LIST"

echo "[Step 4] Compiling Java source files..."
# @sources.txt: compile all source files listed in sources.txt
javac -encoding UTF-8 -cp "$LIB_DIR/*:$BUILD_DIR" -d "$BUILD_DIR" @"$SOURCE_LIST"
JAVAC_EXIT=$?

if [ $JAVAC_EXIT -ne 0 ]; then
    echo "[ERROR] Compilation failed!"
    rm -f "$SOURCE_LIST"
    exit $JAVAC_EXIT
fi

rm -f "$SOURCE_LIST"
echo "[SUCCESS] Compilation finished."

echo "[Step 5] Running $MAIN_CLASS..."
echo "------------------------------------------"
java -cp "$BUILD_DIR:$LIB_DIR/*" "$MAIN_CLASS" "$START_URL" "$NUM_PAGES" "$DB_BASE_PATH" "$STOPWORD_PATH"
JAVA_EXIT=$?

if [ $JAVA_EXIT -ne 0 ]; then
    echo
    echo "[TIP] Program exited with error."
    exit $JAVA_EXIT
fi

echo "[SUCCESS] Spider finished. DB files are under $DB_DIR."
