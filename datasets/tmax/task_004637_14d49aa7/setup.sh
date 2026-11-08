#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make valgrind
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/pipeline

    cat << 'EOF' > /home/user/pipeline/calc.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc < 4) return 1;
    int a = atoi(argv[1]);
    int b = atoi(argv[2]);
    char op = argv[3][0];
    int *res = malloc(sizeof(int));
    if (op == '+') *res = a + b;
    else if (op == '-') *res = a - b;
    else if (op == '*') *res = a * b;
    else { free(res); return 1; }
    printf("%d\n", *res);
    // intentional memory leak: no free(res);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/pipeline/Makefile
all:
	gcc calc.c -o calc
EOF

    cat << 'EOF' > /home/user/pipeline/tests.txt
1,10,5,+
2,20,3,*
3,15,4,-
4,10,10,*
5,25,25,+
EOF

    chown -R user:user /home/user/pipeline
    chmod -R 777 /home/user
