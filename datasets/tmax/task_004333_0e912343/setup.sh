#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential python3-venv
    pip3 install pytest

    mkdir -p /home/user/project/fib_ext
    cd /home/user/project/fib_ext

    cat << 'EOF' > fib_ext.c
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <stdlib.h>

unsigned long long* get_fibs(int n) {
    if (n <= 0) return NULL;
    unsigned long long* fibs = (unsigned long long*)malloc(n * sizeof(unsigned long long));
    fibs[0] = 0;
    if (n > 1) fibs[1] = 1;
    // BUG 1: Undefined behavior / Out of bounds write (i <= n instead of i < n)
    for (int i = 2; i <= n; i++) { 
        fibs[i] = fibs[i-1] + fibs[i-2];
    }
    return fibs;
}

static PyObject* py_get_fibs(PyObject* self, PyObject* args) {
    int n;
    if (!PyArg_ParseTuple(args, "i", &n)) {
        return NULL;
    }

    unsigned long long* fibs = get_fibs(n);
    if (!fibs) {
        Py_RETURN_NONE;
    }

    PyObject* list = PyList_New(n);
    for (int i = 0; i < n; i++) {
        PyList_SetItem(list, i, PyLong_FromUnsignedLongLong(fibs[i]));
    }

    // BUG 2: Memory leak. Missing free call here.

    return list;
}

static PyMethodDef FibMethods[] = {
    {"get_fibs", py_get_fibs, METH_VARARGS, "Get first N Fibonacci numbers"},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fibmodule = {
    PyModuleDef_HEAD_INIT, "fib_ext", NULL, -1, FibMethods
};

PyMODINIT_FUNC PyInit_fib_ext(void) {
    return PyModule_Create(&fibmodule);
}
EOF

    cat << 'EOF' > setup.py
from setuptools import setup, Extension

module1 = Extension('fib_ext', sources = ['fib_ext.c'])

setup (name = 'FibExtension',
       version = '1.0',
       description = 'This is a demo package',
       ext_modules = [module1])
EOF

    cd /home/user/project
    python3 -c "
import sqlite3
conn = sqlite3.connect('data.db')
c = conn.cursor()
c.execute('CREATE TABLE computations (id INTEGER PRIMARY KEY, n_value INTEGER)')
data = [(1, 5), (2, 10), (3, 50), (4, 90)]
c.executemany('INSERT INTO computations VALUES (?, ?)', data)
conn.commit()
conn.close()
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
