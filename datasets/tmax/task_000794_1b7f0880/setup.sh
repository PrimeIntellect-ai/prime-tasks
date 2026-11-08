#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    mkdir -p /home/user/legacy_tool

    cat << 'EOF' > /home/user/legacy_tool/expr_ext.c
#include <Python.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static double do_eval(const char* expr) {
    double a = 0, b = 0;
    char op = 0;
    if (sscanf(expr, "%lf %c %lf", &a, &op, &b) == 3) {
        if (op == '+') return a + b;
        if (op == '-') return a - b;
        if (op == '*') return a * b;
        if (op == '/') return (b != 0.0) ? (a / b) : 0.0;
    }
    return 0.0;
}

static PyObject* py_evaluate(PyObject* self, PyObject* args) {
    const char* expr;
    if (!PyArg_ParseTuple(args, "s", &expr)) {
        return NULL;
    }
    double result = do_eval(expr);
    return PyFloat_FromDouble(result);
}

static PyMethodDef ExprMethods[] = {
    {"evaluate",  py_evaluate, METH_VARARGS, "Evaluate a basic math expression."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef exprmodule = {
    PyModuleDef_HEAD_INIT,
    "expr_ext",
    NULL,
    -1,
    ExprMethods
};

PyMODINIT_FUNC PyInit_expr_ext(void) {
    return PyModule_Create(&exprmodule);
}
EOF

    cat << 'EOF' > /home/user/legacy_tool/config.txt
Timeout: 10.5 * 2.0
MaxRetries: 3.0 + 2.0
Threshold: 100.0 - 15.5
ScaleFactor: 1.0 / 4.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
