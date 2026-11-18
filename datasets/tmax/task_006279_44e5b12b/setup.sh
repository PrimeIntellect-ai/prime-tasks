#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev cron
    pip3 install pytest

    mkdir -p /home/user/logs
    mkdir -p /home/user/bin

    cat << 'EOF' > /home/user/logs/raw_logs.jsonl
{"level": "info", "message": "user \u0061dmin logged in\u0021"}
{"level": "error", "message": "database connection reset"}
{"level": "info", "message": "USER ADMIN LOGGED IN!"}
{"level": "debug", "message": "cache miss for key \u0031\u0032\u0033"}
{"level": "error", "message": "DATABASE connection \u0072eset"}
EOF

    cat << 'EOF' > /home/user/parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

void process_line(char *line) {
    char *msg_start = strstr(line, "\"message\": \"");
    if (!msg_start) return;

    msg_start += 12; // skip past "message": "
    char *msg_end = strchr(msg_start, '"');
    if (!msg_end) return;

    *msg_end = '\0';

    // TODO: Unescape \uXXXX sequences here
    // TODO: Convert to lowercase

    printf("%s\n", msg_start);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <logfile>\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "r");
    if (!f) {
        perror("fopen");
        return 1;
    }

    char buffer[1024];
    while (fgets(buffer, sizeof(buffer), f)) {
        process_line(buffer);
    }

    fclose(f);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
