#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/rpn_calc

    cat << 'EOF' > /home/user/rpn_calc/Makefile
all: rpn_calc

rpn_calc: rpn_calc.c
	gcc -O2 rpn_calc.c -o rpn_calc

clean:
	rm -f rpn_calc
EOF

    cat << 'EOF' > /home/user/rpn_calc/rpn_calc.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;

    double stack[10];
    int top = 0;

    char *token = strtok(argv[1], " ");
    while (token != NULL) {
        if (strcmp(token, "+") == 0) {
            double b = stack[--top];
            double a = stack[--top];
            stack[top++] = a + b;
        } else if (strcmp(token, "-") == 0) {
            double b = stack[--top];
            double a = stack[--top];
            stack[top++] = a - b;
        } else if (strcmp(token, "*") == 0) {
            double b = stack[--top];
            double a = stack[--top];
            stack[top++] = a * b;
        } else if (strcmp(token, "/") == 0) {
            double b = stack[--top];
            double a = stack[--top];
            stack[top++] = a / b;
        } else if (strcmp(token, "^") == 0) {
            double b = stack[--top];
            double a = stack[--top];
            stack[top++] = pow(a, b);
        } else {
            stack[top++] = atof(token);
        }
        token = strtok(NULL, " ");
    }

    if (top == 1) {
        printf("%.4f\n", stack[0]);
        return 0;
    }
    return 1;
}
EOF

    cat << 'EOF' > /home/user/rpn_calc/inputs.txt
3 4 +
10 2 / 5 *
2 3 ^ 4 +
1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 + + + + + + + + + + + + + + +
8 2 / 2 ^
100 10 / 2 /
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
