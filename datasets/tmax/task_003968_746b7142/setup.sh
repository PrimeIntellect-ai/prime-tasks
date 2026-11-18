#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev gcc make sqlite3
    pip3 install pytest

    mkdir -p /home/user/math_migrator
    cd /home/user/math_migrator

    cat << 'EOF' > Makefile
all:
	gcc -shared -o fastmath.so -fPIC fastmath.c $(shell python-config --cflags --ldflags)
EOF

    cat << 'EOF' > fastmath.c
#include <Python.h>
#include <string.h>
#include <stdlib.h>

static PyObject* evaluate_rpn(PyObject* self, PyObject* args) {
    const char* expr;
    if (!PyArg_ParseTuple(args, "s", &expr)) return NULL;

    int stack[10];
    int sp = 0;

    char* expr_copy = strdup(expr);
    char* token = strtok(expr_copy, " ");

    while (token != NULL) {
        if (strcmp(token, "+") == 0) {
            // BUG: No underflow check
            int b = stack[--sp];
            int a = stack[--sp];
            stack[sp++] = a + b;
        } else if (strcmp(token, "*") == 0) {
            // BUG: No underflow check
            int b = stack[--sp];
            int a = stack[--sp];
            stack[sp++] = a * b;
        } else {
            stack[sp++] = atoi(token);
        }
        token = strtok(NULL, " ");
    }

    int result = stack[--sp];
    free(expr_copy);
    return Py_BuildValue("i", result);
}

static PyMethodDef FastMathMethods[] = {
    {"evaluate_rpn", evaluate_rpn, METH_VARARGS, "Evaluate RPN expression."},
    {NULL, NULL, 0, NULL}
};

PyMODINIT_FUNC initfastmath(void) {
    (void) Py_InitModule("fastmath", FastMathMethods);
}
EOF

    cat << 'EOF' > app.py
import fastmath
import sqlite3

expressions = []
with open("input.txt", "r") as f:
    for line in f:
        expressions.append(line.strip())

conn = sqlite3.connect("data.db")
c = conn.cursor()

for i in xrange(len(expressions)):
    expr = expressions[i]
    res = fastmath.evaluate_rpn(expr)
    print "Evaluated", expr, "to", res
    # Legacy schema insert
    c.execute("INSERT INTO history (equation) VALUES (?)", (expr,))

conn.commit()
conn.close()
EOF

    cat << 'EOF' > input.txt
3 4 +
5 6 * 2 +
1 + + +
7 8 *
EOF

    cat << 'EOF' > migrate.sql
ALTER TABLE history RENAME COLUMN equation TO math_expr;
ALTER TABLE history ADD COLUMN result INTEGER;
EOF

    sqlite3 data.db "CREATE TABLE history (id INTEGER PRIMARY KEY, equation TEXT);"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
