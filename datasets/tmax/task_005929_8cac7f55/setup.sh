#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake g++ make valgrind
    pip3 install pytest

    mkdir -p /home/user/polyglot-eval/scripts
    mkdir -p /home/user/polyglot-eval/src
    mkdir -p /home/user/polyglot-eval/tests

    cat << 'EOF' > /home/user/polyglot-eval/scripts/generate_data.py
import sys
def generate():
    for i in range(1, 101):
        print(f"{i} + {i * 2}")
if __name__ == '__main__':
    generate()
EOF

    cat << 'EOF' > /home/user/polyglot-eval/src/ast.h
#ifndef AST_H
#define AST_H

class ASTNode {
public:
    char op;
    int value;
    ASTNode* left;
    ASTNode* right;

    ASTNode(int val);
    ASTNode(char o, ASTNode* l, ASTNode* r);
    ~ASTNode(); // Deletes left and right
};

#endif
EOF

    cat << 'EOF' > /home/user/polyglot-eval/src/ast.cpp
#include "ast.h"

ASTNode::ASTNode(int val) : op('v'), value(val), left(nullptr), right(nullptr) {}

ASTNode::ASTNode(char o, ASTNode* l, ASTNode* r) : op(o), value(0), left(l), right(r) {}

ASTNode::~ASTNode() {
    delete left;
    delete right;
}
EOF

    cat << 'EOF' > /home/user/polyglot-eval/src/evaluator.h
#ifndef EVALUATOR_H
#define EVALUATOR_H

#include "ast.h"

int evaluate(ASTNode node);

#endif
EOF

    cat << 'EOF' > /home/user/polyglot-eval/src/evaluator.cpp
#include "evaluator.h"
#include <stdexcept>

int evaluate(ASTNode node) {
    if (node.op == 'v') {
        return node.value;
    }
    int left_val = 0;
    int right_val = 0;
    if (node.left) {
        left_val = evaluate(*node.left);
    }
    if (node.right) {
        right_val = evaluate(*node.right);
    }

    switch (node.op) {
        case '+': return left_val + right_val;
        case '-': return left_val - right_val;
        case '*': return left_val * right_val;
        case '/': return left_val / right_val;
        default: throw std::runtime_error("Unknown operator");
    }
}
EOF

    cat << 'EOF' > /home/user/polyglot-eval/src/main.cpp
#include <iostream>
#include <string>
#include <sstream>
#include "ast.h"
#include "evaluator.h"

ASTNode* parse(const std::string& line) {
    std::stringstream ss(line);
    int a, b;
    char op;
    if (ss >> a >> op >> b) {
        return new ASTNode(op, new ASTNode(a), new ASTNode(b));
    }
    return nullptr;
}

int main() {
    std::string line;
    while (std::getline(std::cin, line)) {
        if (line.empty()) continue;
        ASTNode* root = parse(line);
        if (root) {
            std::cout << evaluate(*root) << std::endl;
            delete root;
        }
    }
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
