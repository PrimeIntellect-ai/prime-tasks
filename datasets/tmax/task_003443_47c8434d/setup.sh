#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb valgrind
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/log_transformer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void process_line(const char *line) {
    char buf[512];
    strncpy(buf, line, 511);
    buf[511] = '\0';

    // The bug: strtok returns NULL if delimiter is missing, leading to segfault in strlen
    char *timestamp = strtok(buf, "|");
    char *level = strtok(NULL, "|");
    char *message = strtok(NULL, "\n");

    int msg_len = strlen(message);

    printf("{\"timestamp\":\"%s\", \"level\":\"%s\", \"message\":\"%s\", \"msg_len\":%d}\n",
           timestamp, level, message, msg_len);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <logfile>\n", argv[0]);
        return 1;
    }
    char line[512];
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    while (fgets(line, sizeof(line), f)) {
        process_line(line);
    }
    fclose(f);
    return 0;
}
EOF

    python3 -c '
import random
with open("/home/user/large_log.txt", "w") as f:
    for i in range(1, 5000):
        if i == 3482:
            # Preceding line
            f.write("2023-10-25T08:14:02Z|DEBUG|Connection established to backend database\n")
        elif i == 3483:
            # Crashing line (Missing pipes)
            f.write("2023-10-25T08:14:05Z FATAL Out of memory in main thread\n")
        else:
            f.write(f"2023-10-25T00:00:00Z|INFO|Routine log entry number {i}\n")
'

    chmod 644 /home/user/log_transformer.c
    chmod 644 /home/user/large_log.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
