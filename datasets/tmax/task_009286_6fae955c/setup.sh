#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev
    pip3 install pytest requests packaging

    mkdir -p /home/user/pricing_engine
    cd /home/user/pricing_engine

    cat << 'EOF' > ceval.c
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <string.h>
#include <stdlib.h>

static PyObject* eval_expr(PyObject* self, PyObject* args) {
    const char* expr;
    if (!PyArg_ParseTuple(args, "s", &expr)) {
        return NULL;
    }

    char op[10];
    int a, b;
    if (sscanf(expr, "%9s %d %d", op, &a, &b) != 3) {
        PyErr_SetString(PyExc_ValueError, "Invalid expression format");
        return NULL;
    }

    int result = 0;
    if (strcmp(op, "ADD") == 0) result = a + b;
    else if (strcmp(op, "SUB") == 0) result = a - b;
    else if (strcmp(op, "MUL") == 0) result = a * b;
    else if (strcmp(op, "DIV") == 0) {
        if (b == 0) {
            PyErr_SetString(PyExc_ZeroDivisionError, "Division by zero");
            return NULL;
        }
        result = a / b;
    } else {
        PyErr_SetString(PyExc_ValueError, "Unknown operator");
        return NULL;
    }

    return PyLong_FromLong(result);
}

static PyMethodDef CevalMethods[] = {
    {"eval_expr", eval_expr, METH_VARARGS, "Evaluate a prefix expression."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef cevalmodule = {
    PyModuleDef_HEAD_INIT,
    "ceval",
    NULL,
    -1,
    CevalMethods
};

PyMODINIT_FUNC PyInit_ceval(void) {
    return PyModule_Create(&cevalmodule);
}
EOF

    cat << 'EOF' > setup.py
from setuptools import setup, Extension

# BROKEN: Missing sources array and wrong syntax for Extension
module1 = Extension('ceval', source=['wrong.c'])

setup(
    name='pricing_engine',
    version='1.0',
    description='Pricing Engine',
    ext_modules=[module1]
)
EOF

    cat << 'EOF' > engine.py
import requests
from packaging import version
import ceval

def get_and_eval(api_ver):
    if version.parse(api_ver) < version.parse("1.5.0"):
        return -1

    resp = requests.get(f"http://api.internal/rules?v={api_ver}")
    data = resp.json()
    expr = data.get("expression", "")

    return ceval.eval_expr(expr)
EOF

    cat << 'EOF' > requirements.txt
pytest
requests
packaging
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
