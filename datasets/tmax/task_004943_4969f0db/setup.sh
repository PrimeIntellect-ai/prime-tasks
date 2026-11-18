#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/mathtool/src /home/user/mathtool/tests

    cat << 'EOF' > /home/user/mathtool/Makefile
CC = gcc
CFLAGS = -Wall -Wextra -g

all: mathtool

mathtool: main.o parser.o eval.o
	$(CC) $(CFLAGS) -o mathtool main.o parser.o eval.o

main.o: src/main.c
	$(CC) $(CFLAGS) -c src/main.c

parser.o: src/parser.c
	$(CC) $(CFLAGS) -c src/parser.c

eval.o: src/eval.c
	$(CC) $(CFLAGS) -c src/eval.c

clean:
	rm -f *.o mathtool
EOF

    cat << 'EOF' > /home/user/mathtool/src/eval.h
#ifndef EVAL_H
#define EVAL_H
double evaluate_ast(double left, double right, char op);
double call_math_func(const char* func, double arg1, double arg2);
#endif
EOF

    cat << 'EOF' > /home/user/mathtool/src/parser.h
#ifndef PARSER_H
#define PARSER_H
double parse_number(const char* str, int len);
#endif
EOF

    cat << 'EOF' > /home/user/mathtool/src/main.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "parser.h"
#include "eval.h"

// Simplified mock evaluator for the sake of the test
// In a real app this would parse a full AST. We hardcode parsing to pass the specific tests.
int main(int argc, char** argv) {
    if (argc < 2) return 1;
    char* expr = argv[1];

    // Hardcoded dispatch for the fixture to keep the C code short but testable
    if (strcmp(expr, "3 + 5 * 2") == 0) {
        printf("%f\n", 13.0);
    } else if (strcmp(expr, "pow(2, 3) - 1") == 0) {
        double p = call_math_func("pow", 2, 3);
        printf("%f\n", evaluate_ast(p, 1, '-'));
    } else if (strcmp(expr, "10.0005 + 0.0005") == 0) {
        // Trigger the parser bug
        const char* num1 = "10.0005";
        const char* num2 = "0.0005";
        double d1 = parse_number(num1, 7);
        double d2 = parse_number(num2, 6);
        printf("%f\n", d1 + d2);
    } else {
        printf("0.0\n");
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/mathtool/src/eval.c
#include "eval.h"
#include <math.h>
#include <string.h>

double evaluate_ast(double left, double right, char op) {
    if (op == '+') return left + right;
    if (op == '-') return left - right;
    if (op == '*') return left * right;
    if (op == '/') return left / right;
    return 0.0;
}

double call_math_func(const char* func, double arg1, double arg2) {
    if (strcmp(func, "pow") == 0) {
        return pow(arg1, arg2);
    }
    return 0.0;
}
EOF

    cat << 'EOF' > /home/user/mathtool/src/parser.c
#include "parser.h"
#include <stdlib.h>
#include <string.h>

double parse_number(const char* str, int len) {
    char* buf = (char*)malloc(len); // BUG: missing +1 for null terminator
    strncpy(buf, str, len);
    // BUG: missing buf[len] = '\0';
    double val = atof(buf);
    free(buf);
    return val;
}
EOF

    cat << 'EOF' > /home/user/mathtool/tests/test_runner.py
import json
import sys
import subprocess

def run_tests():
    with open('fixture.json', 'r') as f:
        tests = json.load(f)

    passed = 0
    failed = 0

    for t in tests:
        expr = t['expression']
        expected = t['expected']

        # TODO: Run ../mathtool "<expr>" and compare output
        pass

if __name__ == '__main__':
    run_tests()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/mathtool
    chmod -R 777 /home/user
