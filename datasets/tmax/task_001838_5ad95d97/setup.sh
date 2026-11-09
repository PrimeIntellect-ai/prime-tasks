#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libsqlite3-dev
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/legacy_chain_builder.c
#include <stdio.h>
#include <sqlite3.h>

int callback(void *NotUsed, int argc, char **argv, char **azColName) {
    for(int i=0; i<argc; i++){
        printf("%s%s", argv[i] ? argv[i] : "NULL", i == argc-1 ? "" : " -> ");
    }
    printf("\n");
    return 0;
}

int main(int argc, char **argv) {
    sqlite3 *db;
    char *zErrMsg = 0;
    sqlite3_open(argv[1], &db);

    const char *sql = 
        "WITH RECURSIVE chain AS ("
        "  SELECT backup_id as start_id, backup_id as end_id, backup_type as path, size_bytes as total_size "
        "  FROM backups WHERE backup_type = 'FULL' "
        "  UNION ALL "
        "  SELECT c.start_id, b.backup_id, c.path || ',' || b.backup_type, c.total_size + b.size_bytes "
        "  FROM chain c JOIN backups b ON c.end_id = b.parent_id "
        ") "
        "SELECT start_id, end_id, path, total_size FROM chain ORDER BY total_size DESC, start_id ASC, end_id ASC;";

    sqlite3_exec(db, sql, callback, 0, &zErrMsg);
    sqlite3_close(db);
    return 0;
}
EOF

    gcc /app/legacy_chain_builder.c -lsqlite3 -o /app/legacy_chain_builder
    strip /app/legacy_chain_builder
    rm /app/legacy_chain_builder.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
