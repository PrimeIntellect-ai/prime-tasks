#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils jq
    pip3 install pytest

    mkdir -p /home/user/project/src
    mkdir -p /home/user/project/lib
    mkdir -p /home/user/project/bin

    cat << 'EOF' > /home/user/project/config.json
{
  "operation": "sub"
}
EOF

    cat << 'EOF' > /home/user/project/src/main.c
#include <stdio.h>
#include <stdlib.h>

extern int do_math(int a, int b);

int main(int argc, char** argv) {
    if (argc != 3) {
        return 1;
    }
    int a = atoi(argv[1]);
    int b = atoi(argv[2]);
    printf("%d\n", do_math(a, b));
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/project
    chmod -R 777 /home/user
