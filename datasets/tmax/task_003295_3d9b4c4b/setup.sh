#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libc6-dev
    pip3 install pytest

    mkdir -p /home/user/polyglot-data

    cat << 'EOF' > /home/user/polyglot-data/processor.h
#ifndef PROCESSOR_H
#define PROCESSOR_H
char* process_data(const char* input);
#endif
EOF

    cat << 'EOF' > /home/user/polyglot-data/processor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "processor.h"

char* process_data(const char* input) {
    int id = 0, value = 0;
    if (sscanf(input, "id:%d,value:%d", &id, &value) != 2) {
        return NULL;
    }
    value *= 2;
    char* result = malloc(128);
    snprintf(result, 128, "id:%d,value:%d", id, value);
    return result;
}
EOF

    cat << 'EOF' > /home/user/polyglot-data/main.c
#include <stdio.h>
#include <stdlib.h>
#include "processor.h"

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    char* res = process_data(argv[1]);
    if (res) {
        printf("%s\n", res);
        free(res);
    }
    return 0;
}
EOF

    # Using printf to ensure literal tabs are preserved in the Makefile
    printf "all: app\n\nlibprocessor.so: processor.c\n\tgcc -shared -o libprocessor.so processor.c\n\napp: main.c libprocessor.so\n\tgcc -o app main.c\n" > /home/user/polyglot-data/Makefile

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
