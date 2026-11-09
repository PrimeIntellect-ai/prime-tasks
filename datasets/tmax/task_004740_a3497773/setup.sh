#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest hypothesis flask

    mkdir -p /app/vendor/libexpr

    cat << 'EOF' > /app/vendor/libexpr/expr.h
#ifndef EXPR_H
#define EXPR_H

int evaluate_expression(const char* expr, int* out_result);

#endif
EOF

    cat << 'EOF' > /app/vendor/libexpr/parser.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "expr.h"

int parse_and_eval(const char* input, int* out_result) {
    char buf[16];
    /* Vulnerability: buffer overflow */
    strcpy(buf, input);

    int a = 0, b = 0;
    char op = 0;
    if (sscanf(buf, "%d%c%d", &a, &op, &b) == 3) {
        if (op == '+') *out_result = a + b;
        else if (op == '-') *out_result = a - b;
        else return -1;
        return 0;
    }
    return -1;
}
EOF

    cat << 'EOF' > /app/vendor/libexpr/eval.c
#include "expr.h"

extern int parse_and_eval(const char* input, int* out_result);

int evaluate_expression(const char* expr, int* out_result) {
    if (!expr || !out_result) return -1;
    return parse_and_eval(expr, out_result);
}
EOF

    cat << 'EOF' > /app/vendor/libexpr/Makefile
CC = gcc
CFLAGS = -fPIC -Wall -Wextra
LDFLAGS = -shared

all: libexpr.so

libexpr.so: eval.o parser.o
	$(CC) $(LDFLAGS) -o $@ $^

eval.o: eval.c expr.h parser.o
	$(CC) $(CFLAGS) -c eval.c

parser.o: parser.c expr.h eval.o
	$(CC) $(CFLAGS) -c parser.c

clean:
	rm -f *.o *.so
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
