#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/log_processor.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

void process_log_line(const char* log_line) {
    const char* start = strchr(log_line, '"');
    if (!start) return;
    const char* end = strrchr(log_line, '"');
    if (start == end) return;

    char query[50]; // Bug: Hardcoded small buffer
    int len = end - start - 1;

    strncpy(query, start + 1, len);
    query[len] = '\0'; // This will cause memory corruption if len >= 50

    printf("Processed query: %s\n", query);
}

int main() {
    FILE *fp = fopen("/home/user/server.log", "r");
    if (!fp) {
        perror("Failed to open log file");
        return 1;
    }

    char line[256];
    while (fgets(line, sizeof(line), fp)) {
        process_log_line(line);
    }

    fclose(fp);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/server.log
2023-10-01 12:00:00 [INFO] "SELECT * FROM users"
2023-10-01 12:00:01 [WARN] "SELECT id, name FROM items WHERE category='books'"
2023-10-01 12:00:02 [INFO] "UPDATE config SET val=1"
2023-10-01 12:00:03 [ERROR] "SELECT * FROM orders WHERE user_id = 12345 AND status = 'pending' AND created_at > '2023-01-01'"
2023-10-01 12:00:04 [INFO] "DELETE FROM cache"
EOF

    gcc -g -o /home/user/log_processor /home/user/log_processor.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
