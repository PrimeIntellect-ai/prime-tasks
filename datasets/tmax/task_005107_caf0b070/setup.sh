#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make expect libc6-dev
    pip3 install pytest

    mkdir -p /app/miniping-1.2
    mkdir -p /opt/oracle

    cat << 'EOF' > /app/miniping-1.2/main.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    if (strcmp(argv[1], "--init") == 0) {
        char buf[256];
        printf("Set default timeout (ms): ");
        fflush(stdout);
        if (!fgets(buf, sizeof(buf), stdin)) return 1;
        printf("Set max retries: ");
        fflush(stdout);
        if (!fgets(buf, sizeof(buf), stdin)) return 1;
        printf("Enable debug? (y/n): ");
        fflush(stdout);
        if (!fgets(buf, sizeof(buf), stdin)) return 1;
        printf("Configuration saved.\n");
        return 0;
    } else if (strcmp(argv[1], "--check") == 0 && argc == 3) {
        char *payload = argv[2];
        double entropy = 0.0;
        int len = strlen(payload);
        if (len > 0) {
            entropy = log2(len) + sqrt(len);
        }
        printf("Status: OK, Entropy: %f\n", entropy);
        return 0;
    }
    return 1;
}
EOF

    cat << 'EOF' > /app/miniping-1.2/Makefile
CC=gcc
CFLAGS=-Wall -Wextra -O2
LDFLAGS=

all: miniping

miniping: main.o
	$(CC) $(CFLAGS) -o miniping main.o $(LDFLAGS)

main.o: main.c
	$(CC) $(CFLAGS) -c main.c

clean:
	rm -f miniping main.o
EOF

    # Compile the oracle binary with the missing -lm flag
    gcc -Wall -Wextra -O2 /app/miniping-1.2/main.c -o /opt/oracle/miniping_oracle -lm

    # Set permissions for oracle directory
    chmod 700 /opt/oracle

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
