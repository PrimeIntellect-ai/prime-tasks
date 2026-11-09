#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make wget unzip sqlite3
    pip3 install pytest

    # Setup vendored SQLite
    mkdir -p /app/sqlite-amalgamation
    wget https://www.sqlite.org/2023/sqlite-amalgamation-3430200.zip -O /tmp/sqlite.zip
    unzip /tmp/sqlite.zip -d /tmp/
    mv /tmp/sqlite-amalgamation-3430200/* /app/sqlite-amalgamation/
    rm -rf /tmp/sqlite.zip /tmp/sqlite-amalgamation-3430200

    # Create broken Makefile
    cat << 'EOF' > /app/sqlite-amalgamation/Makefile
sqlite3.o: sqlite3.c
	gcc -c sqlite2.c -o sqlite3.o
EOF

    # Setup corpora
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    sqlite3 /app/corpora/clean/clean1.db "CREATE TABLE incremental_backups(id INTEGER PRIMARY KEY, parent_id INTEGER); INSERT INTO incremental_backups VALUES (10, NULL), (50, 10), (100, 50);"
    sqlite3 /app/corpora/evil/evil1.db "CREATE TABLE incremental_backups(id INTEGER PRIMARY KEY, parent_id INTEGER); INSERT INTO incremental_backups VALUES (10, 100), (50, 10), (100, 50);"

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
