#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install pytest setuptools

    mkdir -p /home/user/math_accelerator/src
    mkdir -p /home/user/math_accelerator/math_accelerator

    cat << 'EOF' > /home/user/math_accelerator/src/trib_c.c
#define PY_SSIZE_T_CLEAN
#include <Python.h>

static PyObject* tribonacci(PyObject* self, PyObject* args) {
    int n;
    if (!PyArg_ParseTuple(args, "i", &n)) return NULL;
    if (n == 0) return PyLong_FromLong(0);
    if (n == 1 || n == 2) return PyLong_FromLong(1);

    long long a = 0, b = 1, c = 1, d;
    for (int i = 3; i <= n; i++) {
        d = a + b + c;
        a = b;
        b = c;
        c = d;
    }
    return PyLong_FromLongLong(c);
}

static PyMethodDef TribMethods[] = {
    {"tribonacci", tribonacci, METH_VARARGS, "Calculate tribonacci number."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef tribmodule = {
    PyModuleDef_HEAD_INIT,
    "trib_c",
    NULL,
    -1,
    TribMethods
};

PyMODINIT_FUNC PyInit_trib_c(void) {
    return PyModule_Create(&tribmodule);
}
EOF

    cat << 'EOF' > /home/user/math_accelerator/setup.py
from setuptools import setup, Extension

setup(
    name='math_accelerator',
    version='0.1.0',
    packages=['math_accelerator'],
    # A junior dev deleted the ext_modules configuration here
)
EOF

    touch /home/user/math_accelerator/math_accelerator/__init__.py

    cat << 'EOF' > /home/user/math_accelerator/math_accelerator/trib_py.py
def tribonacci(n):
    # TODO: Implement this
    pass
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
