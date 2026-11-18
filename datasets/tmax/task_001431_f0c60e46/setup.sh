#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev gcc binutils
pip3 install pytest

mkdir -p /home/user/auth_service

sqlite3 /home/user/auth_service/users.db <<EOF
CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT, password TEXT);
INSERT INTO users (username, password) VALUES ('admin', '272e2c2a2832143b3c2f147272');
EOF

cat << 'EOF' > /home/user/auth_service/auth.c
#include <stdio.h>
#include <string.h>
#include <sqlite3.h>

int main(int argc, char **argv) {
    if (argc != 3) return 1;
    sqlite3 *db;
    if (sqlite3_open("users.db", &db)) return 1;

    char query[256];
    sprintf(query, "SELECT * FROM users WHERE username='%s' AND password='%s'", argv[1], argv[2]);

    sqlite3_stmt *stmt;
    sqlite3_prepare_v2(db, query, -1, &stmt, 0);

    if (sqlite3_step(stmt) == SQLITE_ROW) {
        printf("Login successful\n");
    } else {
        printf("Login failed\n");
    }
    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return 0;
}
EOF

cat << 'EOF' > /tmp/hasher.c
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    for(int i = 0; i < strlen(argv[1]); i++) {
        printf("%02x", argv[1][i] ^ 0x4B);
    }
    printf("\n");
    return 0;
}
EOF

gcc /tmp/hasher.c -o /home/user/auth_service/hasher
rm /tmp/hasher.c

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
