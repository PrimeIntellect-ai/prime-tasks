#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils gdb
    pip3 install pytest

    mkdir -p /app/corpus/evil /app/corpus/clean

    cat << 'EOF' > /tmp/vuln_server.c
#include <stdio.h>
#include <string.h>

void parse_cookie(const char *cookie_str) {
    char buffer[64];
    char *session = strstr(cookie_str, "session_id=");
    if (session) {
        session += 11;
        int i = 0;
        while (session[i] != '\0' && session[i] != ';' && session[i] != '\r' && session[i] != '\n') {
            buffer[i] = session[i];
            i++;
        }
        buffer[i] = '\0';
    }
}

int main() {
    return 0; // Stub for static analysis
}
EOF
    gcc -O2 /tmp/vuln_server.c -o /app/vuln_server
    strip /app/vuln_server
    rm /tmp/vuln_server.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
