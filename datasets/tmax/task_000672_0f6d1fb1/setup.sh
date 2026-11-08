#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential sqlite3 wget unzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app/sqlite-src
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil

    # Fetch real sqlite amalgamation
    wget https://www.sqlite.org/2023/sqlite-amalgamation-3430200.zip -O /tmp/sqlite.zip
    unzip /tmp/sqlite.zip -d /tmp/
    cp /tmp/sqlite-amalgamation-3430200/sqlite3.c /app/sqlite-src/
    cp /tmp/sqlite-amalgamation-3430200/sqlite3.h /app/sqlite-src/
    rm -rf /tmp/sqlite.zip /tmp/sqlite-amalgamation-3430200

    cat << 'EOF' > /app/sqlite-src/build.sh
#!/bin/bash
gcc -c sqlite3.c -DSQLITE_OMIT_CTE -O2
ar rcs libsqlite3.a sqlite3.o
EOF
    chmod +x /app/sqlite-src/build.sh

    # Create Clean Corpus (DAGs)
    sqlite3 /home/user/corpora/clean/dag1.db "CREATE TABLE citations (source_id INT, target_id INT); INSERT INTO citations VALUES (1, 2), (2, 3), (3, 4);"
    sqlite3 /home/user/corpora/clean/dag2.db "CREATE TABLE citations (source_id INT, target_id INT); INSERT INTO citations VALUES (10, 20), (10, 30), (20, 40), (30, 40);"

    # Create Evil Corpus (Cycles)
    sqlite3 /home/user/corpora/evil/cycle1.db "CREATE TABLE citations (source_id INT, target_id INT); INSERT INTO citations VALUES (1, 2), (2, 3), (3, 1);"
    sqlite3 /home/user/corpora/evil/cycle2.db "CREATE TABLE citations (source_id INT, target_id INT); INSERT INTO citations VALUES (5, 6), (6, 7), (7, 5), (1, 9);"

    chown -R user:user /app/sqlite-src /home/user/corpora
    chmod -R 777 /home/user
