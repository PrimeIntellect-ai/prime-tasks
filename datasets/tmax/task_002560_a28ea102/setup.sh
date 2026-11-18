#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/log_ingest.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void process_line(char *line) {
    char *ptr = strstr(line, "UTC+");
    if (ptr) {
        char tz[8];
        ptr += 4;
        char *end = ptr;
        while (*end && *end != ' ' && *end != '\n') end++;
        char tmp = *end;
        *end = '\0';
        strcpy(tz, ptr);
        *end = tmp;
    }
}

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    char line[1024];
    while (fgets(line, sizeof(line), f)) {
        process_line(line);
    }
    fclose(f);
    return 0;
}
EOF

    gcc -fno-stack-protector -O0 -o /app/log_ingest /app/log_ingest.c
    strip /app/log_ingest
    rm /app/log_ingest.c

    useradd -m -s /bin/bash user || true

    echo "ELF CORE DUMP DUMMY" > /home/user/crash.core
    echo "[2023-10-12T15:30:00 UTC+9999999999999999] Processing request..." >> /home/user/crash.core

    python3 -c '
with open("/home/user/production.log", "w") as f:
    for i in range(50000):
        f.write("[2023-10-12T15:30:00 UTC+0000] Normal log line\n")
    f.write("[2023-10-12T15:30:00 UTC+9999999999999999] Processing request...\n")
    for i in range(50000):
        f.write("[2023-10-12T15:30:00 UTC+0000] Normal log line\n")
'

    chmod -R 777 /home/user
