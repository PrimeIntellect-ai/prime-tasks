#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/secure-parser
    cd /home/user/secure-parser

    cat << 'EOF' > Makefile
CFLAGS=-Wall -Werror -g

test_runner: evaluate.o test_mock.o
	gcc $(CFLAGS) -o test_runner $^

evaluate.o: evaluate.c ast.h lexer.h parser.h
	gcc $(CFLAGS) -c evaluate.c

test_mock.o: test_mock.c ast.h lexer.h parser.h
	gcc $(CFLAGS) -c test_mock.c

clean:
	rm -f *.o test_runner
EOF

    cat << 'EOF' > ast.h
#ifndef AST_H
#define AST_H

#include "parser.h"

typedef struct ASTNode {
    int type; // 0 for literal, 1 for ADD
    int value;
    struct ASTNode* left;
    struct ASTNode* right;
} ASTNode;

#endif
EOF

    cat << 'EOF' > lexer.h
#ifndef LEXER_H
#define LEXER_H

#include "ast.h"

typedef struct Token {
    int token_type;
} Token;

#endif
EOF

    cat << 'EOF' > parser.h
#ifndef PARSER_H
#define PARSER_H

#include "lexer.h"

typedef struct ParserState {
    Token current_token;
} ParserState;

#endif
EOF

    cat << 'EOF' > evaluate.c
#include <stdlib.h>
#include "ast.h"

int* evaluate_ast(ASTNode* node) {
    int result = 0;
    if (node->type == 0) {
        result = node->value;
    } else if (node->type == 1) {
        int left_val = node->left ? node->left->value : 0;
        int right_val = node->right ? node->right->value : 0;
        result = left_val + right_val;
    }
    return &result; // ERROR: returns address of local variable
}
EOF

    cat << 'EOF' > test_mock.c
#include <stdio.h>
#include <stdlib.h>
#include "ast.h"

// TODO: Implement int get_secret_key() using inline assembly to return 42.

// TODO: Implement main() function as described in the task.
EOF

    chown -R user:user /home/user/secure-parser
    chmod -R 777 /home/user
