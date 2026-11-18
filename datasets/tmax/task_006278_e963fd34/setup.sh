#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /home/user/binaries
    cd /home/user/binaries

    cat << 'EOF' > bin1.c
#include <stdio.h>
const char secret[] __attribute__((section(".secret"))) = "313131";
int main() { return 0; }
EOF
    gcc bin1.c -o bin1

    cat << 'EOF' > bin2.c
#include <stdio.h>
const char secret[] __attribute__((section(".secret"))) = "2337262b361d203b322331311d7b7b";
int main() { return 0; }
EOF
    gcc bin2.c -o bin2 -no-pie -z execstack

    cat << 'EOF' > bin3.c
#include <stdio.h>
const char secret[] __attribute__((section(".secret"))) = "323232";
int main() { return 0; }
EOF
    gcc bin3.c -o bin3 -no-pie

    cat << 'EOF' > bin4.c
#include <stdio.h>
const char secret[] __attribute__((section(".secret"))) = "302d2d361d2321212731311d3a";
int main() { return 0; }
EOF
    gcc bin4.c -o bin4 -no-pie -z execstack

    cat << 'EOF' > bin5.c
#include <stdio.h>
const char secret[] __attribute__((section(".secret"))) = "333333";
int main() { return 0; }
EOF
    gcc bin5.c -o bin5 -z execstack

    rm *.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
