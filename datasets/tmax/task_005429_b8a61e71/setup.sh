#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest websockets

mkdir -p /app
echo -en 'RIFF\x24\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x44\xac\x00\x00\x88\x58\x01\x00\x02\x00\x10\x00data\x00\x00\x00\x00' > /app/telemetry.wav

cat << 'EOF' > /app/libtelemetry.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int initialized = 0;

void init_decoder() {
    initialized = 1;
}

char* decode_audio(const char* filepath) {
    if (!initialized) {
        // Crash if not initialized, simulating the CI bug
        int *p = NULL;
        *p = 42; 
    }

    FILE *f = fopen(filepath, "r");
    if (!f) return NULL;
    fclose(f);

    // "SYSTEM_STABLE_ALL_GREEN" in hex
    const char* payload = "53595354454d5f535441424c455f414c4c5f475245454e";
    char* result = malloc(strlen(payload) + 1);
    strcpy(result, payload);
    return result;
}

void free_string(char* str) {
    if (str) free(str);
}
EOF

chmod -R 777 /app

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
