#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc netcat-openbsd
    pip3 install pytest

    mkdir -p /app/bin

    # Create oracle parser
    cat << 'EOF' > /app/oracle_parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char line[256];
    if (fgets(line, sizeof(line), stdin)) {
        int uptime, cpu, mem;
        if (sscanf(line, "UPTIME:%d:CPU:%d:MEM:%d", &uptime, &cpu, &mem) == 3) {
            const char* status = (cpu < 90 && mem < 90) ? "OK" : "WARN";
            printf("[STAT] U:%d C:%d M:%d %s\n", uptime, cpu, mem, status);
        }
    }
    return 0;
}
EOF
    gcc /app/oracle_parser.c -o /app/bin/oracle_parser
    chmod +x /app/bin/oracle_parser

    # Create dummy emitter and collector
    cat << 'EOF' > /app/status_emitter.py
#!/usr/bin/env python3
import socket
import time

def main():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', 9001))
    s.listen(1)
    while True:
        conn, addr = s.accept()
        conn.sendall(b"UPTIME:1234:CPU:45:MEM:60\n")
        conn.close()

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/status_emitter.py

    cat << 'EOF' > /app/metrics_collector.py
#!/usr/bin/env python3
import socket

def main():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', 9002))
    s.listen(1)
    while True:
        conn, addr = s.accept()
        data = conn.recv(1024)
        if data:
            print(data.decode('utf-8'), end='')
        conn.close()

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/metrics_collector.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
