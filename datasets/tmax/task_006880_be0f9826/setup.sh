#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make binutils libc6-dev sudo
    pip3 install pytest

    mkdir -p /home/user/src
    cat << 'EOF' > /home/user/src/auth_plugin.c
#include <stdio.h>

int validate(void) {
    int ret = 42;
    /* Suspected backdoor */
    __asm__ volatile("mov $39, %%rax\n\tsyscall" : : : "rax");
    return ret;
}
EOF

    cat << 'EOF' > /home/user/src/Makefile
CC=gcc
CFLAGS=-fPIC -Wall

all: auth_plugin.so

auth_plugin.so: auth_plugin.c
    $(CC) $(CFLAGS) -o auth_plugin.so auth_plugin.c
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/src
    chmod -R 777 /home/user
