#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make valgrind libc6-dev
pip3 install pytest

mkdir -p /home/user/libastmath
cd /home/user/libastmath

cat << 'EOF' > Makefile
CC = gcc
CFLAGS = -Wall -g
LDFLAGS = 

ifeq ($(target),embedded)
	CFLAGS += -DEMBEDDED_TARGET
	TARGET = astmath_embedded
else
	TARGET = astmath
endif

all: $(TARGET)

$(TARGET): main.o eval.o
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

main.o: main.c eval.h
	$(CC) $(CFLAGS) -c main.c

eval.o: eval.c eval.h
	$(CC) $(CFLAGS) -c eval.c

clean:
	rm -f *.o astmath astmath_embedded
EOF

cat << 'EOF' > eval.h
#ifndef EVAL_H
#define EVAL_H

typedef enum {
    NODE_VAL,
    NODE_ADD,
    NODE_SUB,
    NODE_MUL,
    NODE_DIV,
    NODE_POW
} NodeType;

typedef struct Node {
    NodeType type;
    double val;
    struct Node *left;
    struct Node *right;
} Node;

Node* parse_rpn(char* expr);
double evaluate_ast(Node* root);
void free_ast(Node* root);

#endif
EOF

cat << 'EOF' > eval.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "eval.h"

Node* create_node(NodeType type, double val, Node* left, Node* right) {
    Node* n = (Node*)malloc(sizeof(Node));
    n->type = type;
    n->val = val;
    n->left = left;
    n->right = right;
    return n;
}

Node* parse_rpn(char* expr) {
    Node* stack[100];
    int top = -1;

    char* expr_copy = strdup(expr);
    char* token = strtok(expr_copy, " ");

    while (token != NULL) {
        if (strcmp(token, "+") == 0) {
            Node* right = stack[top--];
            Node* left = stack[top--];
            stack[++top] = create_node(NODE_ADD, 0, left, right);
        } else if (strcmp(token, "-") == 0) {
            Node* right = stack[top--];
            Node* left = stack[top--];
            stack[++top] = create_node(NODE_SUB, 0, left, right);
        } else if (strcmp(token, "*") == 0) {
            Node* right = stack[top--];
            Node* left = stack[top--];
            stack[++top] = create_node(NODE_MUL, 0, left, right);
        } else if (strcmp(token, "/") == 0) {
            Node* right = stack[top--];
            Node* left = stack[top--];
            stack[++top] = create_node(NODE_DIV, 0, left, right);
        } else if (strcmp(token, "^") == 0) {
            Node* right = stack[top--];
            Node* left = stack[top--];
            stack[++top] = create_node(NODE_POW, 0, left, right);
        } else {
            stack[++top] = create_node(NODE_VAL, atof(token), NULL, NULL);
        }
        token = strtok(NULL, " ");
    }
    free(expr_copy);
    return stack[0];
}

double evaluate_ast(Node* root) {
    if (!root) return 0.0;
    switch (root->type) {
        case NODE_VAL: return root->val;
        case NODE_ADD: return evaluate_ast(root->left) + evaluate_ast(root->right);
        case NODE_SUB: return evaluate_ast(root->left) - evaluate_ast(root->right);
        case NODE_MUL: return evaluate_ast(root->left) * evaluate_ast(root->right);
        case NODE_DIV: return evaluate_ast(root->left) / evaluate_ast(root->right);
        case NODE_POW: 
#ifdef EMBEDDED_TARGET
            // Dummy embedded logic that failed to compile due to a missing semicolon and undeclared var
            int emb_res = (int)evaluate_ast(root->left) ^ (int)evaluate_ast(root->right)
            return (double)emb_res;
#else
            return (int)evaluate_ast(root->left) ^ (int)evaluate_ast(root->right);
#endif
    }
    return 0.0;
}

void free_ast(Node* root) {
    if (!root) return;
    if (root->left) free_ast(root->left);
    if (root->right) free_ast(root->right);
    // BUG: Missing free(root); causing memory leak
}
EOF

cat << 'EOF' > main.c
#include <stdio.h>
#include <stdlib.h>
#include "eval.h"

int main(int argc, char** argv) {
    if (argc < 2) {
        printf("Usage: %s \"rpn expression\"\n", argv[0]);
        return 1;
    }

    Node* ast = parse_rpn(argv[1]);
    double result = evaluate_ast(ast);

    printf("%f\n", result);

    free_ast(ast);
    return 0;
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
