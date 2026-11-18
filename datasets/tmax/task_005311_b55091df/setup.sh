#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make
pip3 install pytest

mkdir -p /home/user/math_system

cat << 'EOF' > /home/user/math_system/Makefile
# Broken Makefile
all:
	gcc -o libeval.so eval.c
EOF

cat << 'EOF' > /home/user/math_system/eval.c
#include <stdio.h>
#include <math.h>

#define OP_VAL 0
#define OP_ADD 1
#define OP_SUB 2
#define OP_MUL 3
#define OP_DIV 4
#define OP_POW 5

typedef struct {
    int op;
    double value;
    int left_idx;
    int right_idx;
} Node;

double evaluate_ast(Node* nodes, int current_idx) {
    if (current_idx < 0) return 0.0;

    Node* n = &nodes[current_idx];

    if (n->op == OP_VAL) {
        return n->value;
    }

    double left_val = evaluate_ast(nodes, n->left_idx);
    double right_val = evaluate_ast(nodes, n->right_idx);

    switch (n->op) {
        case OP_ADD: return left_val + right_val;
        case OP_SUB: return left_val - right_val;
        case OP_MUL: return left_val * right_val;
        // OP_DIV and OP_POW are missing and need to be implemented by the agent
    }

    return 0.0;
}
EOF

cat << 'EOF' > /home/user/math_system/formulas.json
[
  {
    "id": "eq1",
    "expr": {
      "op": "add",
      "left": {"op": "val", "value": 10.0},
      "right": {"op": "val", "value": 5.0}
    }
  },
  {
    "id": "eq2",
    "expr": {
      "op": "pow",
      "left": {"op": "val", "value": 2.0},
      "right": {"op": "val", "value": 8.0}
    }
  },
  {
    "id": "eq3",
    "expr": {
      "op": "div",
      "left": {
        "op": "mul",
        "left": {"op": "val", "value": 100.0},
        "right": {"op": "val", "value": 3.0}
      },
      "right": {
        "op": "sub",
        "left": {"op": "val", "value": 15.0},
        "right": {"op": "val", "value": 15.0}
      }
    }
  },
  {
    "id": "eq4",
    "expr": {
      "op": "div",
      "left": {"op": "val", "value": 42.0},
      "right": {"op": "val", "value": 7.0}
    }
  }
]
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
