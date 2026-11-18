#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make binutils gdb libc6-dev
    pip3 install pytest

    mkdir -p /home/user/forensic_project/lib
    mkdir -p /home/user/forensic_project/include

    # 1. Create the proprietary auth library (with debug symbols)
    cat << 'EOF' > /tmp/auth.c
void generate_token(int seed, char* out_buffer, int max_len) {
    if (max_len > 10) {
        out_buffer[0] = 'T';
        out_buffer[1] = 'O';
        out_buffer[2] = 'K';
        out_buffer[3] = '\0';
    }
}
EOF
    gcc -g -shared -fPIC /tmp/auth.c -o /home/user/forensic_project/lib/libauth.so
    rm /tmp/auth.c

    # 2. Create the corrupted header
    cat << 'EOF' > /home/user/forensic_project/include/auth.h
#ifndef AUTH_H
#define AUTH_H

// TODO: Fix this signature!
int generate_token(void);

#endif
EOF

    # 3. Create extractor.c with the non-thread-safe strtok
    cat << 'EOF' > /home/user/forensic_project/extractor.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "include/auth.h"

char* parse_log_entry(const char* log_line) {
    char* log_copy = strdup(log_line);
    char* token = strtok(log_copy, ",");
    char* last_token = NULL;

    while (token != NULL) {
        last_token = token;
        token = strtok(NULL, ",");
    }

    char* result = last_token ? strdup(last_token) : NULL;
    free(log_copy);
    return result;
}
EOF

    # 4. Create main.c
    cat << 'EOF' > /home/user/forensic_project/main.c
#include <stdio.h>
#include <stdlib.h>
#include "include/auth.h"

extern char* parse_log_entry(const char* log_line);

int main() {
    char token[256];
    generate_token(42, token, 256);
    printf("Auth token: %s\n", token);
    return 0;
}
EOF

    # 5. Create a broken Makefile (missing -I and -L flags)
    cat << 'EOF' > /home/user/forensic_project/Makefile
CC = gcc
CFLAGS = -Wall -lpthread

all: forensic_tool

forensic_tool: main.o extractor.o
	$(CC) $(CFLAGS) -o forensic_tool main.o extractor.o -lauth

main.o: main.c
	$(CC) $(CFLAGS) -c main.c

extractor.o: extractor.c
	$(CC) $(CFLAGS) -c extractor.c

test: forensic_tool
	LD_LIBRARY_PATH=./lib ./forensic_tool

clean:
	rm -f *.o forensic_tool
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/forensic_project
    chmod -R 777 /home/user
