#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make espeak ffmpeg
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/mathlib
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # 1. Create C library source
    cat << 'EOF' > /home/user/mathlib/parser.c
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include <math.h>

double eval_expr(const char* expr);
double parse_sum(const char** p);
double parse_product(const char** p);
double parse_factor(const char** p);

double parse_factor(const char** p) {
    while (isspace(**p)) (*p)++;
    if (**p == '(') {
        (*p)++;
        double res = parse_sum(p);
        if (**p == ')') (*p)++;
        return res;
    }
    char* end;
    double val = strtod(*p, &end);
    *p = end;
    while (isspace(**p)) (*p)++;
    if (**p == '^') {
        (*p)++;
        double exponent = parse_factor(p);
        val = pow(val, exponent);
    }
    return val;
}

double parse_product(const char** p) {
    double res = parse_factor(p);
    while (1) {
        while (isspace(**p)) (*p)++;
        if (**p == '*') {
            (*p)++;
            res *= parse_factor(p);
        } else if (**p == '/') {
            (*p)++;
            res /= parse_factor(p);
        } else {
            break;
        }
    }
    return res;
}

double parse_sum(const char** p) {
    double res = parse_product(p);
    while (1) {
        while (isspace(**p)) (*p)++;
        if (**p == '+') {
            (*p)++;
            res += parse_product(p);
        } else if (**p == '-') {
            (*p)++;
            res -= parse_product(p);
        } else {
            break;
        }
    }
    return res;
}

double eval_expr(const char* expr) {
    const char* p = expr;
    return parse_sum(&p);
}
EOF

    # Create Makefile with intentional error (missing -lm)
    cat << 'EOF' > /home/user/mathlib/Makefile
all: libmathparser.so

libmathparser.so: parser.c
	gcc -shared -fPIC -Wl,--no-undefined -o libmathparser.so parser.c

clean:
	rm -f libmathparser.so
EOF

    # 2. Generate Audio Directive
    espeak -w /app/directive.wav "The maximum allowed path weight is fifty"

    # 3. Create JSON Corpus
    # Clean v1
    cat << 'EOF' > /app/corpus/clean/clean_v1.json
{
  "version": 1,
  "nodes": {
    "A": {"expr": "10 + 5"},
    "B": {"expr": "2 ^ 3"}
  },
  "dependencies": {
    "A": ["B"],
    "B": []
  }
}
EOF

    # Clean v2
    cat << 'EOF' > /app/corpus/clean/clean_v2.json
{
  "version": 2,
  "nodes": {
    "X": {"expr": "20"},
    "Y": {"expr": "30"}
  },
  "deps": {
    "X": ["Y"],
    "Y": []
  }
}
EOF

    # Evil Cycle
    cat << 'EOF' > /app/corpus/evil/evil_cycle.json
{
  "version": 2,
  "nodes": {
    "A": {"expr": "10"},
    "B": {"expr": "10"}
  },
  "deps": {
    "A": ["B"],
    "B": ["A"]
  }
}
EOF

    # Evil Threshold Exceeded
    cat << 'EOF' > /app/corpus/evil/evil_heavy.json
{
  "version": 1,
  "nodes": {
    "A": {"expr": "30"},
    "B": {"expr": "25"}
  },
  "dependencies": {
    "A": ["B"],
    "B": []
  }
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
