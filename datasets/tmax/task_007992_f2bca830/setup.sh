#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create malware.dmp
    head -c 1024 /dev/urandom > malware.dmp
    echo -n "C2_START{" >> malware.dmp
    echo -ne "\x20\x23\x26\x6f\x26\x2d\x2f\x23\x2b\x2c\x6c\x3a\x3b\x38" >> malware.dmp
    echo -n "}" >> malware.dmp
    head -c 512 /dev/urandom >> malware.dmp

    # Create log_parser.c
    cat << 'EOF' > log_parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    fseek(f, 0, SEEK_END);
    long fsize = ftell(f);
    fseek(f, 0, SEEK_SET);

    char *buf = malloc(fsize + 1);
    fread(buf, 1, fsize, f);
    fclose(f);

    for(long i=0; i < fsize - 3; i++) {
        if((unsigned char)buf[i] == 0xDE && 
           (unsigned char)buf[i+1] == 0xAD && 
           (unsigned char)buf[i+2] == 0xBE && 
           (unsigned char)buf[i+3] == 0xEF) {
            int *crash = NULL;
            *crash = 0xdead;
        }
    }

    free(buf);
    return 0;
}
EOF
    gcc -o log_parser log_parser.c
    rm log_parser.c

    # Create trigger.log
    head -c 2000 /dev/zero > trigger.log
    echo -ne "\xDE\xAD\xBE\xEF" >> trigger.log
    head -c 2000 /dev/zero >> trigger.log

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
