#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb
    pip3 install pytest

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/libuptime.c
#include <string.h>
#include <stdio.h>

int check_uptime(const char* hostname) {
    char buffer[16];
    // Intentional buffer overflow for strings >= 16 chars (including null terminator)
    strcpy(buffer, hostname); 
    return 200;
}
EOF

    gcc -shared -o /home/user/app/libuptime.so -fPIC /home/user/app/libuptime.c -fno-stack-protector
    rm /home/user/app/libuptime.c

    cat << 'EOF' > /home/user/app/monitor.py
import ctypes
import os

lib = ctypes.CDLL('/home/user/app/libuptime.so')

def monitor_host(hostname):
    # This will crash if hostname is too long
    return lib.check_uptime(hostname.encode('utf-8'))
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
