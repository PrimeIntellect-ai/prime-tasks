#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /app/fast-url-parser-1.2.0

    cat << 'EOF' > /app/fast-url-parser-1.2.0/Makefile
all: libfastparser.so

libfastparser.so: parser.o utils.o
	gcc -shared -o libfastparser.so parser.o utils.o

parser.o: parser.c utils.h
	gcc -fPIC -c parser.c

# Deliberate circular/incorrect dependency introduced here:
utils.o: utils.c parser.o
	gcc -fPIC -c utils.c

clean:
	rm -f *.o *.so
EOF

    cat << 'EOF' > /app/fast-url-parser-1.2.0/utils.h
#ifndef UTILS_H
#define UTILS_H
void clean_path(const char* input, char* output);
#endif
EOF

    cat << 'EOF' > /app/fast-url-parser-1.2.0/utils.c
#include "utils.h"
#include <string.h>

void clean_path(const char* input, char* output) {
    int i = 0, j = 0;
    while (input[i] != '\0' && j < 255) {
        if (input[i] == '.' && input[i+1] == '.' && input[i+2] == '/') {
            i += 3; // skip ../
        } else {
            output[j++] = input[i++];
        }
    }
    output[j] = '\0';
}
EOF

    cat << 'EOF' > /app/fast-url-parser-1.2.0/parser.c
#include "utils.h"
// dummy file to justify multiple objects
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
