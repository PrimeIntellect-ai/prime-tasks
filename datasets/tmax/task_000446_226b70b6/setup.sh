#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make binutils wget
    pip3 install pytest

    mkdir -p /app/vendor/inih-53
    cd /app/vendor/inih-53
    wget https://raw.githubusercontent.com/benhoyt/inih/r53/ini.c
    wget https://raw.githubusercontent.com/benhoyt/inih/r53/ini.h

    cat << 'EOF' > /app/vendor/inih-53/Makefile
CC = gcc
CFLAGS = -O2
AR = ar

all: libinih.a

ini.o: ini.c ini.h
	$(CC) $(CFLAGS) -c ini.c -o ini.o

libinih.a: ini.o
        ar rvs libinih.a INI.O

clean:
	rm -f ini.o libinih.a
EOF

    cat << 'EOF' > /app/oracle_parser.c
#include <stdio.h>
#include <string.h>
#include "ini.h"
static int handler(void* user, const char* section, const char* name, const char* value) {
    printf("[%s] %s=%s\n", section, name, value);
    return 1;
}
int main() {
    ini_parse_stream((ini_reader)fgets, stdin, handler, NULL);
    return 0;
}
EOF

    gcc -O2 /app/oracle_parser.c /app/vendor/inih-53/ini.c -o /app/oracle_parser -I/app/vendor/inih-53
    strip /app/oracle_parser
    rm /app/oracle_parser.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
