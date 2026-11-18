#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ e2fsprogs
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.cpp
#include <iostream>
#include <string>
#include <cctype>
#include <cstdlib>

class Parser {
    const char* p;
    double parseFactor() {
        while (isspace(*p)) p++;
        int sign = 1;
        if (*p == '-') { sign = -1; p++; }
        else if (*p == '+') { p++; }
        while (isspace(*p)) p++;

        double val = 0;
        if (*p == '(') {
            p++;
            val = parseExpr();
            while (isspace(*p)) p++;
            if (*p == ')') p++;
        } else {
            char* end;
            val = std::strtod(p, &end);
            p = end;
        }
        return sign * val;
    }
    double parseTerm() {
        double val = parseFactor();
        while (true) {
            while (isspace(*p)) p++;
            if (*p == '*') { p++; val *= parseFactor(); }
            else if (*p == '/') { p++; val /= parseFactor(); }
            else break;
        }
        return val;
    }
public:
    double parseExpr() {
        double val = parseTerm();
        while (true) {
            while (isspace(*p)) p++;
            if (*p == '+') { p++; val += parseTerm(); }
            else if (*p == '-') { p++; val -= parseTerm(); }
            else break;
        }
        return val;
    }
    double parse(const char* str) {
        p = str;
        return parseExpr();
    }
};

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    Parser parser;
    std::cout << parser.parse(argv[1]) << std::endl;
    return 0;
}
EOF
    g++ -O2 /tmp/oracle.cpp -o /app/math_oracle
    strip /app/math_oracle

    mkdir -p /home/user/src
    mkdir -p /tmp/ext4_src

    cat << 'EOF' > /tmp/ext4_src/expr_parser.h
#ifndef EXPR_PARSER_H
#define EXPR_PARSER_H
class Parser {
    const char* p;
    double parseFactor();
    double parseTerm();
public:
    double parseExpr();
    double parse(const char* str);
};
#endif
EOF

    dd if=/dev/zero of=/home/user/ext4_dump.img bs=1M count=10
    mke2fs -t ext4 -d /tmp/ext4_src /home/user/ext4_dump.img
    debugfs -w -R "rm expr_parser.h" /home/user/ext4_dump.img

    cat << 'EOF' > /home/user/src/math_evaluator.cpp
#include <iostream>
#include <string>
#include <cctype>
#include <cstdlib>
#include "expr_parser.h"

double Parser::parseFactor() {
    while (isspace(*p)) p++;
    int sign = 1;
    if (*p == '-') { sign = -1; p++; }

    double val = 0;
    if (*p == '(') {
        p++;
        val = parseExpr();
        if (*p == ')') p++;
    } else {
        char* end;
        val = std::strtod(p, &end);
        p = end;
    }
    return sign * val;
}

double Parser::parseTerm() {
    double val = parseFactor();
    while (true) {
        while (isspace(*p)) p++;
        if (*p == '*') { p++; val *= parseFactor(); }
        else if (*p == '/') { p++; val /= parseFactor(); }
        else break;
    }
    return val;
}

double Parser::parseExpr() {
    double val = parseTerm();
    while (true) {
        while (isspace(*p)) p++;
        if (*p == '+') { p++; val += parseTerm(); }
        else if (*p == '-') { p++; val -= parseTerm(); }
        else break;
    }
    return val;
}

double Parser::parse(const char* str) {
    p = str;
    return parseExpr();
}

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    Parser parser;
    std::cout << parser.parse(argv[1]) << std::endl;
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
