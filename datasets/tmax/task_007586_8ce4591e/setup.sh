#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/sec_lib

    cat << 'EOF' > /home/user/sec_lib/urlsec.h
#ifndef URLSEC_H
#define URLSEC_H
void encode_xss(const char *input, char *output);
#endif
EOF

    cat << 'EOF' > /home/user/sec_lib/urlsec.c
#include "urlsec.h"
#include <string.h>

void encode_xss(const char *input, char *output) {
    while (*input) {
        if (*input == '<') {
            strcat(output, "%3C");
            output += 3;
        } else if (*input == '>') {
            strcat(output, "%3E");
            output += 3;
        } else {
            *output = *input;
            output++;
        }
        input++;
    }
    *output = '\0';
}
EOF

    cat << 'EOF' > /home/user/sec_lib/main.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "urlsec.h"

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    char buffer[1024] = {0};
    encode_xss(argv[1], buffer);
    printf("%s\n", buffer);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/sec_lib/Makefile
all: urltool

liburlsec.so: urlsec.c
	gcc -shared -o liburlsec.so urlsec.c

urltool: main.c liburlsec.so
	gcc -o urltool main.c
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
