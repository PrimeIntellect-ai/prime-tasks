#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/math_feature

    cat << 'EOF' > /home/user/math_feature/Makefile
rpn_vm: rpn_vm.c
    gcc -O2 -o rpn_vm rpn_vm.c
clean:
    rm -f rpn_vm
EOF

    cat << 'EOF' > /home/user/math_feature/rpn_vm.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#define MAX_STACK 1000

int stack[MAX_STACK];
int top = -1;

void push(int val) {
    if (top < MAX_STACK - 1) {
        stack[++top] = val;
    }
}

int pop() {
    if (top >= 0) {
        return stack[top--];
    }
    return 0;
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s \"<rpn_expression>\"\n", argv[0]);
        return 1;
    }

    char *expr = argv[1];
    char *token = strtok(expr, " ");

    while (token != NULL) {
        if (isdigit(token[0]) || (token[0] == '-' && isdigit(token[1]))) {
            push(atoi(token));
        } else {
            int val1 = pop();
            int val2 = pop();
            switch (token[0]) {
                case '+': push(val2 + val1); break;
                case '-': push(val1 - val2); break; // BUG: Should be val2 - val1
                case '*': push(val2 * val1); break;
                case '/': push(val1 / val2); break; // BUG: Should be val2 / val1
            }
        }
        token = strtok(NULL, " ");
    }

    printf("%d\n", pop());
    return 0;
}
EOF

    chmod -R 777 /home/user
