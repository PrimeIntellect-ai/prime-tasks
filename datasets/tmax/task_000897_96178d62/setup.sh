#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git build-essential
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <unistd.h>
int main() {
    while(1) sleep(1);
    return 0;
}
EOF
    gcc -o /app/telemetry_oracle /app/oracle.c
    strip /app/telemetry_oracle
    rm /app/oracle.c

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/telemetry_server/src
    cd /home/user/telemetry_server
    git init
    git config user.name "Dev"
    git config user.email "dev@example.com"

    cat << 'EOF' > Makefile
all: server
server: src/server.c src/parser.c
	gcc -o server src/server.c src/parser.c
EOF

    cat << 'EOF' > src/server.c
#include <stdio.h>
#include <unistd.h>
void sanitize_utf8(unsigned char *str, int len);
int main() {
    while(1) sleep(1);
    return 0;
}
EOF

    cat << 'EOF' > src/parser.c
#include <stdio.h>
void sanitize_utf8(unsigned char *str, int len) {
    for(int i=0; i<len; i++) {
        if(str[i] > 127) str[i] = '?';
    }
}
EOF

    cat << 'EOF' > README.md
# Telemetry Server
EOF

    git add .
    git commit -m "Initial commit"

    for i in $(seq 2 142); do
        echo "Update $i" >> README.md
        git add README.md
        git commit -m "Commit $i"
    done

    cat << 'EOF' > src/parser.c
#include <stdio.h>
void sanitize_utf8(unsigned char *str, int len) {
    for(int i=0; i<len; ) {
        if(str[i] > 127) {
            str[i] = '?';
        } else {
            i++;
        }
    }
}
EOF
    git add src/parser.c
    git commit -m "Update parser logic for UTF-8 handling"

    for i in $(seq 144 200); do
        echo "Update $i" >> README.md
        git add README.md
        git commit -m "Commit $i"
    done

    chown -R user:user /home/user
    chmod -R 777 /home/user
