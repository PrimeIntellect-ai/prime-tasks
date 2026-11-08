#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libsqlite3-dev sqlite3
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create SQLite DB
    sqlite3 backup_meta.db <<EOF
CREATE TABLE files(id INTEGER PRIMARY KEY, parent_id INTEGER, name TEXT, metadata TEXT);
INSERT INTO files VALUES(1, NULL, 'root', '{"type": "dir", "size": 0}');
INSERT INTO files VALUES(2, 1, 'file1.txt', '{"type": "file", "size": 150}');
INSERT INTO files VALUES(3, 1, 'subdir', '{"type": "dir", "size": 0}');
INSERT INTO files VALUES(4, 3, 'file2.txt', '{"type": "file", "size": 300}');
INSERT INTO files VALUES(5, 1, 'file3.txt', '{"type": "file", "size": 550}');
INSERT INTO files VALUES(6, NULL, 'other_root', '{"type": "dir", "size": 0}');
INSERT INTO files VALUES(7, 6, 'file4.txt', '{"type": "file", "size": 9999}');
EOF

    # Create buggy C program
    cat << 'EOF' > check_backup.c
#include <stdio.h>
#include <stdlib.h>
#include <sqlite3.h>

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    sqlite3 *db;
    if (sqlite3_open("/home/user/backup_meta.db", &db)) return 1;

    char query[1024];
    // Bug: f.parent_id = f.id instead of f.parent_id = t.id
    sprintf(query, "WITH RECURSIVE tree AS ("
                   "SELECT id, metadata FROM files WHERE id = %s "
                   "UNION ALL "
                   "SELECT f.id, f.metadata FROM files f, tree t WHERE f.parent_id = f.id) "
                   "SELECT sum(CAST(json_extract(metadata, '$.size') AS INTEGER)) FROM tree WHERE json_extract(metadata, '$.type') = 'file';", argv[1]);

    sqlite3_stmt *res;
    if (sqlite3_prepare_v2(db, query, -1, &res, 0) != SQLITE_OK) return 1;

    if (sqlite3_step(res) == SQLITE_ROW) {
        printf("%d\n", sqlite3_column_int(res, 0));
    }

    sqlite3_finalize(res);
    sqlite3_close(db);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
