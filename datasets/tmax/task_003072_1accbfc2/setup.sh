#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    int stack[100];
    int top = 0;
    char *token = strtok(argv[1], " ");
    while (token != NULL) {
        if (strcmp(token, "+") == 0) {
            stack[top-2] = stack[top-2] + stack[top-1]; top--;
        } else if (strcmp(token, "-") == 0) {
            stack[top-2] = stack[top-2] - stack[top-1]; top--;
        } else if (strcmp(token, "*") == 0) {
            stack[top-2] = stack[top-2] * stack[top-1]; top--;
        } else if (strcmp(token, "/") == 0) {
            if (stack[top-1] == 0) return 1;
            stack[top-2] = stack[top-2] / stack[top-1]; top--;
        } else {
            stack[top++] = atoi(token);
        }
        token = strtok(NULL, " ");
    }
    printf("%d\n", stack[0]);
    return 0;
}
EOF
    gcc -O2 /tmp/oracle.c -o /app/rpn_oracle
    strip /app/rpn_oracle

    mkdir -p /home/user/src
    cat << 'EOF' > /home/user/src/rpn.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    int stack[100];
    int top = 0;
    char *token = strtok(argv[1], " ");
    while (token != NULL) {
        if (strcmp(token, "+") == 0) {
            stack[top-2] = stack[top-2] + stack[top-1]; top--;
        } else if (strcmp(token, "-") == 0) {
            stack[top-2] = stack[top-1] - stack[top-2]; top--;
        } else if (strcmp(token, "*") == 0) {
            stack[top-2] = stack[top-2] * stack[top-1]; top--;
        } else if (strcmp(token, "/") == 0) {
            if (stack[top-1] == 0) return 1;
            stack[top-2] = stack[top-1] / stack[top-2]; top--;
        } else {
            stack[top++] = atoi(token);
        }
        token = strtok(NULL, " ");
    }
    printf("%d\n", stack[0]);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/src/Makefile
all:
    gcc rpn.c rpn_calc
EOF
    # Convert tab to spaces to ensure Makefile is broken
    sed -i 's/\t/    /g' /home/user/src/Makefile

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
