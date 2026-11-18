#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make binutils
    pip3 install pytest

    mkdir -p /home/user/gateway
    cd /home/user/gateway

    cat << 'EOF' > validate.h
#ifndef VALIDATE_H
#define VALIDATE_H

int validate_request(const char* endpoint);

#endif
EOF

    cat << 'EOF' > validate.c
#include <stdio.h>
#include <string.h>
#include "validate.h"

int validate_request(const char* endpoint) {
    if (strncmp(endpoint, "/api/", 5) == 0) {
        return 1; // Valid and within rate limit
    }
    return 0; // Invalid
}
EOF

    cat << 'EOF' > gateway.c
#include <stdio.h>
#include "validate.h"

int main(int argc, char** argv) {
    if (argc < 2) {
        printf("{\"error\": \"Missing endpoint\"}\n");
        return 1;
    }

    if (validate_request(argv[1])) {
        printf("{\"status\": 200, \"message\": \"Request forwarded successfully\"}\n");
    } else {
        printf("{\"status\": 403, \"error\": \"Rate limit exceeded or invalid endpoint\"}\n");
    }
    return 0;
}
EOF

    cat << 'EOF' > Makefile
CC = gcc
CFLAGS = -Wall -Werror

all: gateway

libvalidate.so: validate.c
	$(CC) $(CFLAGS) -shared -fPIC -o $@ $<

gateway: gateway.c libvalidate.so
	$(CC) $(CFLAGS) -o $@ $< -L. -lvalidate

clean:
	rm -f gateway libvalidate.so
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/gateway
    chmod -R 777 /home/user
