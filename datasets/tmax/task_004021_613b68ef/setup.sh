#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git make gcc espeak
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/log_parser
    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean

    # Generate audio file
    espeak -w /app/incident.wav "ECHO DELTA SEVEN"

    # Create customer.wal
    echo "CORRUPTED WAL DATA" > /app/customer.wal

    # Setup dummy library for linking
    gcc -shared -o /usr/lib/libaudio_v2.so -x c /dev/null

    # Setup log_parser git repo
    cd /home/user/log_parser
    git init
    git config user.name "Admin"
    git config user.email "admin@example.com"

    cat << 'EOF' > parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc >= 4 && strcmp(argv[1], "--key") == 0) {
        char key[100] = {0};
        for(int i=2; i<argc-1; i++) {
            strcat(key, argv[i]);
            if (i < argc-2) strcat(key, " ");
        }
        if (strcasecmp(key, "ECHO DELTA SEVEN") == 0 || strcasecmp(key, "ECHODELTA7") == 0) {
            printf("{\"status\": \"recovered\", \"records\": [{\"id\": 1, \"fault\": \"OOM\"}, {\"id\": 2, \"fault\": \"TIMEOUT\"}]}\n");
            return 0;
        }
    }

    int payload_len = 5;
    for (int i = 0; i < payload_len; i++) {
        // do nothing
    }
    return 0;
}
EOF

    cat << 'EOF' > Makefile
LDFLAGS = -laudio_v2

parser: parser.c
	gcc -o parser parser.c $(LDFLAGS)

test: parser
	./parser
EOF

    git add parser.c Makefile
    git commit -m "Initial working commit"
    git tag v1.0

    # Introduce off-by-one bug
    sed -i 's/i < payload_len/i <= payload_len/' parser.c
    sed -i 's/\/\/ do nothing/if (i == payload_len) { int *p = NULL; *p = 0; }/' parser.c
    git add parser.c
    git commit -m "Update parser loop logic"

    # Introduce dependency conflict
    sed -i 's/-laudio_v2/-laudio_legacy/' Makefile
    git add Makefile
    git commit -m "Update Makefile dependencies"

    # Create corpus files
    printf "\xAA\x03\x01\x02\x03" > /app/corpus/clean/valid1.bin
    printf "\xAA\x00" > /app/corpus/clean/valid2.bin

    printf "\xAA\x03\x01\x02\x03\x04" > /app/corpus/evil/trailing.bin
    printf "\xAA\x03\x01\x02" > /app/corpus/evil/truncated.bin
    printf "\xBB\x03\x01\x02\x03" > /app/corpus/evil/badmagic.bin

    # Setup user
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
