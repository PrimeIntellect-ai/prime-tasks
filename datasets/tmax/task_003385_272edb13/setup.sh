#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/pr_review

    cat << 'EOF' > /home/user/pr_review/eval_crc.h
#ifndef EVAL_CRC_H
#define EVAL_CRC_H

#include <string>
#include <cstdint>

uint8_t calculate_crc8(const std::string& data);
int evaluate_expr(const std::string& expr);

#endif
EOF

    cat << 'EOF' > /home/user/pr_review/eval_crc.cpp
#include "eval_crc.h"
#include <stack>
#include <cctype>

uint8_t calculate_crc8(const std::string& data) {
    uint8_t crc = 0;
    for (char c : data) {
        crc ^= c;
        for (int i = 0; i < 8; ++i) {
            if (crc & 0x80) {
                crc = (crc << 1) ^ 0x70; // BUG: Should be 0x07
            } else {
                crc <<= 1;
            }
        }
    }
    return crc;
}

int evaluate_expr(const std::string& expr) {
    std::stack<int> values;
    std::stack<char> ops;

    auto apply_op = [](int a, int b, char op) {
        if (op == '+') return a + b;
        if (op == '*') return a * b;
        return 0;
    };

    auto precedence = [](char op) {
        if (op == '+') return 1;
        if (op == '*') return 1; // BUG: Should be 2
        return 0;
    } // BUG: Missing semicolon

    for (size_t i = 0; i < expr.length(); ++i) {
        if (std::isdigit(expr[i])) {
            values.push(expr[i] - '0');
        } else {
            while (!ops.empty() && precedence(ops.top()) >= precedence(expr[i])) {
                int val2 = values.top(); values.pop();
                int val1 = values.top(); values.pop();
                char op = ops.top(); ops.pop();
                values.push(apply_op(val1, val2, op));
            }
            ops.push(expr[i]);
        }
    }

    while (!ops.empty()) {
        int val2 = values.top(); values.pop();
        int val1 = values.top(); values.pop();
        char op = ops.top(); ops.pop();
        values.push(apply_op(val1, val2, op));
    }

    return values.top();
}
EOF

    cat << 'EOF' > /home/user/pr_review/test_runner.cpp
#include "eval_crc.h"
#include <iostream>

void run_test(const std::string& expr, int expected_val, uint8_t expected_crc) {
    int val = evaluate_expr(expr);
    uint8_t crc = calculate_crc8(expr);

    if (val == expected_val && crc == expected_crc) {
        std::cout << "PASS: " << expr << " = " << val << " (CRC: " << (int)crc << ")\n";
    } else {
        std::cout << "FAIL: " << expr << " | Expected " << expected_val << " / CRC " << (int)expected_crc 
                  << " | Got " << val << " / CRC " << (int)crc << "\n";
    }
}

int main() {
    run_test("2+3*4", 14, 187);
    run_test("5*2+3", 13, 222);
    run_test("1+1+1", 3, 26);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/pr_review/Makefile
all: test_runner

test_runner: eval_crc.o test_runner.o
    g++ -o test_runner eval_crc.o test_runner.o

eval_crc.o: eval_crc.cpp
    g++ -c eval_crc.cpp

test_runner.o: test_runner.cpp
    g++ -c test_runner.cpp

clean:
    rm -f *.o test_runner
EOF

    sed -i 's/^\t/    /' /home/user/pr_review/Makefile

    chmod -R 777 /home/user
