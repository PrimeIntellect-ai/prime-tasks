#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake gcc make espeak
    pip3 install pytest

    mkdir -p /app/math_engine/src
    mkdir -p /app/math_engine/include

    # Create the audio spec file
    espeak -w /app/operator_spec.wav "We introduce a custom operator denoted by the at symbol. The expression A at B is evaluated as A squared plus B."

    # Create the oracle program
    cat << 'EOF' > /app/oracle_eval
#!/usr/bin/env python3
import sys
import re

def tokenize(expr):
    return re.findall(r'\d+|[+\-*@]', expr)

def parse_and_eval(expr):
    tokens = tokenize(expr)

    i = 0
    while i < len(tokens):
        if tokens[i] in ('*', '@'):
            op = tokens[i]
            left = int(tokens[i-1])
            right = int(tokens[i+1])
            if op == '*':
                res = left * right
            else:
                res = left * left + right
            tokens = tokens[:i-1] + [str(res)] + tokens[i+2:]
            i -= 1
        else:
            i += 1

    i = 0
    while i < len(tokens):
        if tokens[i] in ('+', '-'):
            op = tokens[i]
            left = int(tokens[i-1])
            right = int(tokens[i+1])
            if op == '+':
                res = left + right
            else:
                res = left - right
            tokens = tokens[:i-1] + [str(res)] + tokens[i+2:]
            i -= 1
        else:
            i += 1

    return int(tokens[0])

if __name__ == '__main__':
    if len(sys.argv) > 1:
        print(parse_and_eval(sys.argv[1]))
EOF
    chmod +x /app/oracle_eval

    # Create CMakeLists.txt with intentional errors
    cat << 'EOF' > /app/math_engine/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(math_engine)

add_library(mathast SHARED src/eval.c src/serialize.c src/parser.c)
target_include_directories(mathast PUBLIC include)

add_executable(eval_tool src/main.c)
# Intentionally broken linkage
target_link_libraries(eval_tool mathast_wrong_name)
EOF

    # Create include/ast.h
    cat << 'EOF' > /app/math_engine/include/ast.h
#ifndef AST_H
#define AST_H
#include <stdint.h>

typedef enum {
    NODE_NUM,
    NODE_ADD,
    NODE_SUB,
    NODE_MUL,
    NODE_AT
} NodeType;

typedef struct ASTNode {
    NodeType type;
    int64_t value;
    struct ASTNode* left;
    struct ASTNode* right;
} ASTNode;

ASTNode* parse_expr(const char* expr);
int64_t evaluate_node(ASTNode* node);
int serialize_ast(ASTNode* root, char** buffer, int* size);
ASTNode* deserialize_ast(const char* buffer, int size);

#endif
EOF

    # Create src/eval.c
    cat << 'EOF' > /app/math_engine/src/eval.c
#include "ast.h"
#include <stdlib.h>

int64_t evaluate_node(ASTNode* node) {
    if (!node) return 0;
    if (node->type == NODE_NUM) return node->value;
    int64_t left = evaluate_node(node->left);
    int64_t right = evaluate_node(node->right);
    if (node->type == NODE_ADD) return left + right;
    if (node->type == NODE_SUB) return left - right;
    if (node->type == NODE_MUL) return left * right;
    // @ operator is missing!
    return 0;
}
EOF

    # Create src/serialize.c
    cat << 'EOF' > /app/math_engine/src/serialize.c
#include "ast.h"
#include <stdlib.h>

int serialize_ast(ASTNode* root, char** buffer, int* size) {
    *buffer = NULL;
    *size = 0;
    return 0; // Stub
}

ASTNode* deserialize_ast(const char* buffer, int size) {
    return NULL; // Stub
}
EOF

    # Create src/parser.c
    cat << 'EOF' > /app/math_engine/src/parser.c
#include "ast.h"
#include <stdlib.h>
#include <ctype.h>

static ASTNode* make_node(NodeType type, ASTNode* left, ASTNode* right) {
    ASTNode* n = calloc(1, sizeof(ASTNode));
    n->type = type; n->left = left; n->right = right;
    return n;
}

static ASTNode* make_num(int64_t val) {
    ASTNode* n = calloc(1, sizeof(ASTNode));
    n->type = NODE_NUM; n->value = val;
    return n;
}

static const char* p;

static ASTNode* parse_primary() {
    while(isspace(*p)) p++;
    int64_t val = 0;
    while(isdigit(*p)) { val = val * 10 + (*p - '0'); p++; }
    return make_num(val);
}

static ASTNode* parse_term() {
    ASTNode* left = parse_primary();
    while(1) {
        while(isspace(*p)) p++;
        if (*p == '*') {
            p++; left = make_node(NODE_MUL, left, parse_primary());
        } else if (*p == '@') {
            p++; left = make_node(NODE_AT, left, parse_primary());
        } else {
            break;
        }
    }
    return left;
}

ASTNode* parse_expr(const char* expr) {
    p = expr;
    ASTNode* left = parse_term();
    while(1) {
        while(isspace(*p)) p++;
        if (*p == '+') {
            p++; left = make_node(NODE_ADD, left, parse_term());
        } else if (*p == '-') {
            p++; left = make_node(NODE_SUB, left, parse_term());
        } else {
            break;
        }
    }
    return left;
}
EOF

    # Create src/main.c
    cat << 'EOF' > /app/math_engine/src/main.c
#include "ast.h"
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    ASTNode* root = parse_expr(argv[1]);
    char* buf = NULL;
    int size = 0;
    serialize_ast(root, &buf, &size);
    ASTNode* new_root = deserialize_ast(buf, size);
    int64_t res = evaluate_node(new_root);
    printf("%lld\n", (long long)res);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
