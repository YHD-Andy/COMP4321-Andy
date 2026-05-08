COMP4321 Phase 1 - Build and Execution Guide

1. Prerequisites
- OS: Windows (PowerShell/CMD) or Linux (bash)
- Java: JDK 8 or above (javac and java must be available in PATH)
- Project root: this folder (contains lib/, src/, search-engine/, p1.bat, p1.sh)

2. Current Project Structure (relevant folders)
- Source code: src/main/java
- Stopword file: src/main/resource/stopwords.txt
- Third-party jars: lib
- Compiled classes output: search-engine/WEB-INF/classes
- JDBM database output: search-engine/WEB-INF/db

3. Build and Run the Spider

3.1 Windows (batch script)
- In project root, run:
  p1.bat
- This script will:
  - clean search-engine/WEB-INF/classes
  - compile all Java files in src/main/java
  - run Phase1Spider with default arguments

3.2 Linux (shell script)
- In project root, run:
  chmod +x p1.sh
  ./p1.sh
- This script performs the same steps as p1.bat.

3.3 Manual commands (without script)

Windows:
1) Compile
   javac -encoding UTF-8 -cp "lib/*;search-engine/WEB-INF/classes" -d search-engine/WEB-INF/classes src/main/java/*.java
2) Run spider
   java -cp "search-engine/WEB-INF/classes;lib/*" Phase1Spider "https://www.cse.ust.hk/~kwtleung/COMP4321/testpage.htm" 30 "search-engine/WEB-INF/db/phase1_30" "src/main/resource/stopwords.txt"

Linux:
1) Compile
   find src/main/java -type f -name "*.java" > sources.txt
   javac -encoding UTF-8 -cp "lib/*:search-engine/WEB-INF/classes" -d search-engine/WEB-INF/classes @sources.txt
   rm -f sources.txt
2) Run spider
   java -cp "search-engine/WEB-INF/classes:lib/*" Phase1Spider "https://www.cse.ust.hk/~kwtleung/COMP4321/testpage.htm" 30 "search-engine/WEB-INF/db/phase1_30" "src/main/resource/stopwords.txt"

Spider arguments:
java Phase1Spider <startUrl> <numPages> <dbBasePath> <stopwordPath>

4. Build and Run the Test Program

Test program: Phase1Dump

4.1 Execute after spider finishes

Windows:
java -cp "search-engine/WEB-INF/classes;lib/*" Phase1Dump "search-engine/WEB-INF/db/phase1_30" "spider result.txt"

Linux:
java -cp "search-engine/WEB-INF/classes:lib/*" Phase1Dump "search-engine/WEB-INF/db/phase1_30" "spider result.txt"

4.2 Program arguments
java Phase1Dump <dbBasePath> <outputFile>

If no arguments are provided, the program uses its internal defaults.

5. Outputs
- Database files are created under search-engine/WEB-INF/db
- The default dump file is spider result.txt in project root

6. Notes
- The spider uses BFS traversal and builds index/link structures in JDBM tables.
- Re-running the spider on existing DB supports incremental updates based on page last-modified time.
