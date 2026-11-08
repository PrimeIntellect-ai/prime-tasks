#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/legacy_tool.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <signal.h>
#include <unistd.h>

void dump_memory() {
    FILE *f = fopen("/home/user/mem.dump", "wb");
    if (f) {
        char junk1[120];
        memset(junk1, 0x00, 120);
        fwrite(junk1, 1, 120, f);
        const char* token = "SUPPORT-TOKEN-9X8A-2B1C-4D5E";
        fwrite(token, 1, strlen(token), f);
        char junk2[500];
        memset(junk2, 0xFF, 500);
        fwrite(junk2, 1, 500, f);
        fclose(f);
    }
}

void segfault_handler(int sig) {
    dump_memory();
    exit(139);
}

int main(int argc, char **argv) {
    signal(SIGSEGV, segfault_handler);
    if (argc != 2) {
        printf("Usage: %s <input>\n", argv[0]);
        return 1;
    }

    if (strncmp(argv[1], "TEST", 4) == 0 && strlen(argv[1]) > 25) {
        raise(SIGSEGV);
    }

    printf("Processed input successfully.\n");
    return 0;
}
EOF

    gcc -o /home/user/legacy_tool /home/user/legacy_tool.c
    rm /home/user/legacy_tool.c
    chmod +x /home/user/legacy_tool

    chmod -R 777 /home/user
