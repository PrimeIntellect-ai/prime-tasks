#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc sqlite3 libsqlite3-dev
    pip3 install pytest

    mkdir -p /home/user/src
    mkdir -p /home/user/data
    mkdir -p /home/user/secure

    # Create the secret flag
    echo "FLAG{c_sec_aud1t_pwn}" > /home/user/secure/flag.txt

    # Create the SQLite database
    sqlite3 /home/user/data/users.db <<EOF
CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT, enc_token INTEGER);
INSERT INTO users (username, enc_token) VALUES ('testuser', 19275);
INSERT INTO users (username, enc_token) VALUES ('admin', 34039);
EOF

    # Create the vulnerable C source
    cat << 'EOF' > /home/user/src/backend.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sqlite3.h>

unsigned short custom_encrypt(unsigned short plaintext, unsigned short key) {
    // Simple vulnerable custom cipher (XOR)
    return plaintext ^ key;
}

void do_login(const char *username) {
    sqlite3 *db;
    char *err_msg = 0;
    sqlite3_stmt *res;

    if (sqlite3_open("/home/user/data/users.db", &db) != SQLITE_OK) {
        printf("Cannot open database\n");
        return;
    }

    // SQL INJECTION VULNERABILITY
    char sql[256];
    sprintf(sql, "SELECT enc_token FROM users WHERE username = '%s';", username);

    if (sqlite3_prepare_v2(db, sql, -1, &res, 0) == SQLITE_OK) {
        while (sqlite3_step(res) == SQLITE_ROW) {
            printf("Encrypted Token: %d\n", sqlite3_column_int(res, 0));
        }
    } else {
        printf("SQL Error\n");
    }
    sqlite3_finalize(res);
    sqlite3_close(db);
}

void admin_panel(unsigned short token, const char *cmd) {
    // Hardcoded admin token expectation for demonstration
    if (token != 0xDEAD) {
        printf("Access Denied.\n");
        return;
    }

    // COMMAND INJECTION VULNERABILITY
    char sys_cmd[256];
    sprintf(sys_cmd, "echo Executing: %s", cmd);
    system(sys_cmd);
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Usage: %s <action> [args...]\n", argv[0]);
        return 1;
    }

    if (strcmp(argv[1], "login") == 0 && argc == 3) {
        do_login(argv[2]);
    } else if (strcmp(argv[1], "admin") == 0 && argc == 4) {
        unsigned short token = (unsigned short)strtoul(argv[2], NULL, 0);
        admin_panel(token, argv[3]);
    }

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
