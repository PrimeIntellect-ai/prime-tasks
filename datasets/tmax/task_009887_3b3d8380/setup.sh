#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/calcgraph/tests

    cat << 'EOF' > /home/user/calcgraph/Makefile
CC=gcc
CFLAGS=-Wall -Werror -g

all: calcgraph

calcgraph: main.o graph.o
	$(CC) $(CFLAGS) -o calcgraph main.o graph.o

main.o: main.c
	$(CC) $(CFLAGS) -c main.c

graph.o: graph.c
	$(CC) $(CFLAGS) -c graph.c

eval.o: eval.c
	$(CC) $(CFLAGS) -c eval.c

clean:
	rm -f *.o calcgraph
EOF

    cat << 'EOF' > /home/user/calcgraph/graph.h
#ifndef GRAPH_H
#define GRAPH_H

typedef enum { OP_VAL, OP_ADD, OP_MUL, OP_SUB } OpType;

typedef struct Node {
    int id;
    OpType op;
    int val;
    struct Node* left;
    struct Node* right;
} Node;

Node* create_node(int id, OpType op, int val);
void link_nodes(Node* parent, Node* left, Node* right);

#endif
EOF

    cat << 'EOF' > /home/user/calcgraph/graph.c
#include "graph.h"
// Bug: missing include stdlib.h, causes implicit declaration of malloc error under -Werror

Node* create_node(int id, OpType op, int val) {
    Node* n = (Node*)malloc(sizeof(Node));
    n->id = id;
    n->op = op;
    n->val = val;
    n->left = NULL;
    n->right = NULL;
    return n;
}

void link_nodes(Node* parent, Node* left, Node* right) {
    parent->left = left;
    parent->right = right;
}
EOF

    cat << 'EOF' > /home/user/calcgraph/eval.h
#ifndef EVAL_H
#define EVAL_H
#include "graph.h"
int evaluate_graph(Node* root);
#endif
EOF

    cat << 'EOF' > /home/user/calcgraph/eval.c
#include "eval.h"

int evaluate_graph(Node* root) {
    if (!root) return 0;

    if (root->op == OP_VAL) {
        return root->val;
    }

    int left_val = evaluate_graph(root->left);
    int right_val = evaluate_graph(root->right);

    if (root->op == OP_ADD) return left_val + right_val;
    if (root->op == OP_SUB) return left_val - right_val;
    if (root->op == OP_MUL) return left_val + right_val; // BUG: Should be left_val * right_val

    return 0;
}
EOF

    cat << 'EOF' > /home/user/calcgraph/main.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "graph.h"
#include "eval.h"

// Hardcoded parsing for simplicity in this task.
// Maps a filename to a preconstructed graph.
int main(int argc, char** argv) {
    if (argc < 2) return 1;
    char* file = argv[1];
    Node* root = NULL;

    if (strstr(file, "test1.cg")) {
        root = create_node(1, OP_ADD, 0);
        Node* l = create_node(2, OP_VAL, 10);
        Node* r = create_node(3, OP_VAL, 15);
        link_nodes(root, l, r);
    } else if (strstr(file, "test2.cg")) {
        root = create_node(1, OP_MUL, 0);
        Node* l = create_node(2, OP_VAL, 6);
        Node* r = create_node(3, OP_VAL, 7);
        link_nodes(root, l, r);
    } else if (strstr(file, "test3.cg")) {
        root = create_node(1, OP_SUB, 0);
        Node* l = create_node(2, OP_MUL, 0);
        Node* r = create_node(3, OP_VAL, 5);
        Node* ll = create_node(4, OP_VAL, 10);
        Node* lr = create_node(5, OP_VAL, 10);
        link_nodes(l, ll, lr);
        link_nodes(root, l, r);
    } else {
        return 1;
    }

    int result = evaluate_graph(root);
    printf("%d\n", result);
    return 0;
}
EOF

    touch /home/user/calcgraph/tests/test1.cg
    touch /home/user/calcgraph/tests/test2.cg
    touch /home/user/calcgraph/tests/test3.cg

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
