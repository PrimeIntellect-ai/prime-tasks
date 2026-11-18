#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc valgrind
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/src
    cat << 'EOF' > /home/user/src/parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    char* key;
    char* value;
} Record;

int main(int argc, char** argv) {
    if(argc != 2) return 1;
    FILE* f = fopen(argv[1], "r");
    if(!f) return 1;

    Record* r = malloc(sizeof(Record));
    char buffer[256];
    if (fgets(buffer, 256, f)) {
        char* token = strtok(buffer, "=");
        if (token) r->key = strdup(token);
        token = strtok(NULL, "\n");
        if (token) r->value = strdup(token);
    }
    printf("Loaded: %s = %s\n", r->key ? r->key : "null", r->value ? r->value : "null");

    // Intentional memory leak: missing free(r->key) and free(r->value)
    free(r);
    fclose(f);
    return 0;
}
EOF

    echo "app_mode=production" > /home/user/data.txt
    echo "2.1.4" > /home/user/version.txt

    chmod -R 777 /home/user
