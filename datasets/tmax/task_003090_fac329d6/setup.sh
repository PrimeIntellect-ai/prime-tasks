#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/deploy
    mkfifo /home/user/deploy/data.fifo

    cat << 'EOF' > /home/user/deploy/daemon.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main() {
    FILE *fifo = fopen("/home/user/deploy/data.fifo", "r");
    if (!fifo) return 1;

    FILE *log = fopen("/home/user/deploy/processed.log", "a");
    if (!log) return 1;

    // Ensure line buffering
    setvbuf(log, NULL, _IOLBF, 0);

    char buffer[256];
    while (fgets(buffer, sizeof(buffer), fifo)) {
        buffer[strcspn(buffer, "\n")] = 0; // strip newline

        if (strcmp(buffer, "SHUTDOWN") == 0) {
            fclose(fifo);
            fclose(log);
            return 0; // Clean exit
        }

        if (strcmp(buffer, "POISON") == 0) {
            // Intentional crash
            char *crash = NULL;
            *crash = 'x'; 
        }

        if (strlen(buffer) > 0) {
            fprintf(log, "PROCESSED: %s\n", buffer);
        }
    }

    fclose(fifo);
    fclose(log);
    return 1; // Abnormal exit if FIFO closes unexpectedly
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
