#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc espeak
    pip3 install pytest

    mkdir -p /app

    # Generate audio file
    espeak -w /app/sysadmin_memo.wav "Hello, this is the previous admin. The secret salt for the new port mapping algorithm is five eight four two. Make sure to update the documentation. Bye."

    # Create and compile oracle
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <string.h>
int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    int sum = 0;
    for(int i=0; i<strlen(argv[1]); i++) {
        sum += (int)argv[1][i];
    }
    int port = ((sum + 5842) % 1000) + 8000;
    printf("%d\n", port);
    return 0;
}
EOF
    gcc -O2 -o /app/port_mapper_oracle /tmp/oracle.c
    strip /app/port_mapper_oracle || true
    chmod +x /app/port_mapper_oracle
    rm /tmp/oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
