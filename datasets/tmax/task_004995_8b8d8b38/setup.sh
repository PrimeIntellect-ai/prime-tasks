#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/parser.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main() {
    char line[256];
    char path[256] = "";
    char op[256] = "";
    long bytes = 0;
    int has_bytes = 0;

    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\r\n")] = 0;
        if (strcmp(line, "BEGIN_WAL_RECORD") == 0) {
            path[0] = '\0';
            op[0] = '\0';
            bytes = 0;
            has_bytes = 0;
        } else if (strncmp(line, "PATH: ", 6) == 0) {
            strcpy(path, line + 6);
        } else if (strncmp(line, "OP: ", 4) == 0) {
            strcpy(op, line + 4);
        } else if (strncmp(line, "BYTES: ", 7) == 0) {
            bytes = atol(line + 7);
            has_bytes = 1;
        } else if (strcmp(line, "END_WAL_RECORD") == 0) {
            if (strcmp(op, "SKIP") == 0 || strcmp(op, "DELETE") == 0) {
                continue;
            }
            if (strcmp(op, "ARCHIVE") == 0 || strcmp(op, "COMPRESS") == 0) {
                long kb = has_bytes ? (bytes / 1024) : 0;
                printf("%s,%s,%ld\n", path, op, kb);
            }
        }
    }
    return 0;
}
EOF

    gcc -O2 /tmp/parser.c -o /app/backup_wal_parser
    strip /app/backup_wal_parser
    rm /tmp/parser.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
