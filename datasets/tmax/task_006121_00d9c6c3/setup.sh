#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project/bin
    mkdir -p /home/user/project/libs/v1
    mkdir -p /home/user/project/libs/v2
    mkdir -p /home/user/project/migrations

    # Create dummy shared libs and binary
    cat << 'EOF' > /home/user/project/libs/v1/libcalc.c
int calculate(int input) { return input * 2; }
EOF
    cat << 'EOF' > /home/user/project/libs/v2/libcalc.c
int calculate(int input) { return input * 3; }
EOF

    gcc -shared -fPIC -o /home/user/project/libs/v1/libcalc.so /home/user/project/libs/v1/libcalc.c
    gcc -shared -fPIC -o /home/user/project/libs/v2/libcalc.so /home/user/project/libs/v2/libcalc.c

    cat << 'EOF' > /home/user/project/bin/calculator.c
#include <stdio.h>
#include <stdlib.h>
extern int calculate(int);
int main(int argc, char** argv) {
    if(argc > 1) {
        printf("%d\n", calculate(atoi(argv[1])));
    }
    return 0;
}
EOF

    gcc -o /home/user/project/bin/calculator /home/user/project/bin/calculator.c -L/home/user/project/libs/v1 -lcalc

    # Create migrations
    cat << 'EOF' > /home/user/project/migrations/01_init.sql
CREATE TABLE settings (factor INTEGER);
EOF
    cat << 'EOF' > /home/user/project/migrations/02_insert.sql
INSERT INTO settings (factor) VALUES (7);
EOF

    chown -R user:user /home/user/project
    chmod -R 777 /home/user
