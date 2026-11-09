#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /home/user/ci_pipeline

    cat << 'EOF' > /home/user/ci_pipeline/expr_parser.h
#ifndef EXPR_PARSER_H
#define EXPR_PARSER_H
#include <string>

int evaluate_expression(const std::string& expr);

#endif
EOF

    cat << 'EOF' > /home/user/ci_pipeline/expr_parser.cpp
#include "expr_parser.h"
#include <sstream>

int evaluate_expression(const std::string& expr) {
    std::stringstream ss(expr);
    int left, right;
    char op;

    ss >> left >> op >> right;

    if (op == '+') return left + right;
    if (op == '-') return right - left; // BUG: Should be left - right
    if (op == '*') return left * right;

    return 0;
}
EOF

    cat << 'EOF' > /home/user/ci_pipeline/main.cpp
#include <iostream>
#include <string>
#include <thread>
#include <vector>
#include <atomic>
#include "expr_parser.h"

std::atomic<int> failed_tests(0);

void run_test(const std::string& expr, int expected) {
    int result = evaluate_expression(expr);
    if (result != expected) {
        std::cerr << "FAIL: " << expr << " evaluated to " << result << " instead of " << expected << std::endl;
        failed_tests++;
    }
}

int main(int argc, char** argv) {
    if (argc > 1 && std::string(argv[1]) == "test") {
        std::vector<std::thread> threads;

        threads.push_back(std::thread(run_test, "10 + 5", 15));
        threads.push_back(std::thread(run_test, "20 - 5", 15));
        threads.push_back(std::thread(run_test, "100 - 90", 10));
        threads.push_back(std::thread(run_test, "4 * 5", 20));

        for (auto& t : threads) {
            t.join();
        }

        if (failed_tests == 0) {
            std::cout << "ALL TESTS PASSED" << std::endl;
            return 0;
        } else {
            std::cout << failed_tests << " TESTS FAILED" << std::endl;
            return 1;
        }
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/ci_pipeline/Makefile
CXX = g++
CXXFLAGS = -std=c++11 -pthread

all: evaluator

# BUG: Missing expr_parser.o in the command
evaluator: main.o expr_parser.o
	$(CXX) $(CXXFLAGS) -o evaluator main.o

main.o: main.cpp
	$(CXX) $(CXXFLAGS) -c main.cpp

expr_parser.o: expr_parser.cpp
	$(CXX) $(CXXFLAGS) -c expr_parser.cpp

clean:
	rm -f *.o evaluator
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
