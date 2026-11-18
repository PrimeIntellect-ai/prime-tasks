#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev gcc
    pip3 install pytest hypothesis setuptools

    mkdir -p /home/user/mathparser_mobile/src
    cd /home/user/mathparser_mobile

    cat << 'EOF' > src/ops.h
#ifndef OPS_H
#define OPS_H
double add(double a, double b) { return a + b; }
double mul(double a, double b) { return a * b; }
#endif
EOF

    cat << 'EOF' > src/parser.c
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <math.h>
#include "ops.h"

static PyObject* evaluate_expression(PyObject* self, PyObject* args) {
    double a, b;
    if (!PyArg_ParseTuple(args, "dd", &a, &b)) {
        return NULL;
    }
    // simple math op combining add, mul, and pow (requires libm)
    double result = pow(add(a, b), 2) + mul(a, b);
    return PyFloat_FromDouble(result);
}

static PyMethodDef MathParserMethods[] = {
    {"evaluate",  evaluate_expression, METH_VARARGS, "Evaluate a math expression."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef mathparsermodule = {
    PyModuleDef_HEAD_INIT, "mathparser", NULL, -1, MathParserMethods
};

PyMODINIT_FUNC PyInit_mathparser(void) {
    return PyModule_Create(&mathparsermodule);
}
EOF

    cat << 'EOF' > test_parser.py
import pytest
from hypothesis import given, strategies as st
import mathparser

@given(st.floats(min_value=-100, max_value=100), st.floats(min_value=-100, max_value=100))
def test_evaluate(a, b):
    # Expected: (a+b)^2 + (a*b)
    expected = ((a + b) ** 2) + (a * b)
    result = mathparser.evaluate(a, b)
    assert abs(result - expected) < 1e-6
EOF

    cat << 'EOF' > setup.py
import os
import hashlib
from setuptools import setup, Extension

ENV_VERSION = "1.10.2"
MIN_VERSION = "1.5.0"

# Bug 1: Flawed string-based semantic version comparison
if ENV_VERSION < MIN_VERSION:
    raise RuntimeError(f"Environment version {ENV_VERSION} is less than minimum required {MIN_VERSION}")

# Bug 2: Checksum validation bug (reads as text, not binary)
def verify_checksum(filepath, expected_hash):
    hasher = hashlib.sha256()
    with open(filepath, 'r') as f:
        hasher.update(f.read().encode('utf-8'))
    if hasher.hexdigest() != expected_hash:
        raise RuntimeError("Checksum mismatch for " + filepath)

# Pre-computed correct sha256 for ops.h
expected_ops_hash = "6eb54dfebf81216d62325372337a6b2edc77f884144be7d656096bfd6904c6e9"
verify_checksum("src/ops.h", expected_ops_hash)

# Bug 3: Missing math library linking
mathparser_module = Extension('mathparser',
                              sources=['src/parser.c'])

setup(name='mathparser_mobile',
      version='1.0',
      description='Math parser mobile extension',
      ext_modules=[mathparser_module])
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
