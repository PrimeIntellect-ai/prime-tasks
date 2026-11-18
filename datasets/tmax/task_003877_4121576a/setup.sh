#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-dev python3-setuptools build-essential
pip3 install pytest

mkdir -p /home/user/math_extension

cat << 'EOF' > /home/user/math_extension/c_math.c
#include <Python.h>
#include <string.h>
#include <stdlib.h>

static PyObject* eval_expr(PyObject* self, PyObject* args) {
    char* expr;
    if (!PyArg_ParseTuple(args, "s", &expr)) {
        return NULL;
    }

    char op;
    int a, b;
    sscanf(expr, "%c %d %d", &op, &a, &b);

    int result = 0;
    if (op == '+') result = a + b;
    else if (op == '-') result = a - b;
    else if (op == '*') result = a * b;
    else if (op == '/') result = a / b;

    return PyInt_FromLong(result);
}

static PyMethodDef MathMethods[] = {
    {"eval_expr",  eval_expr, METH_VARARGS, "Evaluate prefix expression."},
    {NULL, NULL, 0, NULL}
};

PyMODINIT_FUNC initc_math(void) {
    (void) Py_InitModule("c_math", MathMethods);
}
EOF

cat << 'EOF' > /home/user/math_extension/setup.py
from setuptools import setup, Extension

module1 = Extension('c_math', sources = ['c_math.c'])

setup(name = 'c_math',
      version = '1.0',
      description = 'Math expression evaluator',
      ext_modules = [module1])
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
