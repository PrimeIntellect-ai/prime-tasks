#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb libc6-dev
    pip3 install pytest

    mkdir -p /home/user/bin
    mkdir -p /home/user/.local/lib

    cat << 'EOF' > /home/user/libauth.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void check_auth_env() {
    char *mode = getenv("AUTH_MODE");
    if (mode == NULL || strcmp(mode, "DEBUG") != 0) {
        fprintf(stderr, "[FATAL] Authentication mode not set properly. Exiting.\n");
        exit(1);
    }
}
EOF

    gcc -shared -fPIC -o /home/user/.local/lib/libauth.so /home/user/libauth.c

    cat << 'EOF' > /home/user/suspicious_parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern void check_auth_env();

void parse_name_field(const char *input) {
    char local_buffer[64];
    // Vulnerable function: strcpy into fixed buffer
    strcpy(local_buffer, input);
    printf("Parsed name: %s\n", local_buffer);
}

int main(int argc, char *argv[]) {
    check_auth_env();

    if (argc != 2) {
        printf("Usage: %s <config_file>\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "r");
    if (!f) {
        perror("Failed to open file");
        return 1;
    }

    char header[256];
    if (fgets(header, sizeof(header), f) == NULL) {
        return 1;
    }

    if (strncmp(header, "SECURE_CONF_v1", 14) != 0) {
        printf("Invalid magic header.\n");
        return 1;
    }

    char line[512];
    if (fgets(line, sizeof(line), f) != NULL) {
        if (strncmp(line, "NAME:", 5) == 0) {
            parse_name_field(line + 5);
        }
    }

    fclose(f);
    return 0;
}
EOF

    gcc -g -O0 -fno-stack-protector -o /home/user/bin/suspicious_parser /home/user/suspicious_parser.c -L/home/user/.local/lib -lauth

    rm /home/user/libauth.c /home/user/suspicious_parser.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
