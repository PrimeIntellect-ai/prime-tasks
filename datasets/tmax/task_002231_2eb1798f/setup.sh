#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install pytest

    mkdir -p /app/libstatutils-1.2.0

    cat << 'EOF' > /app/libstatutils-1.2.0/statutils.c
#include <Python.h>
#include <math.h>

static PyObject* variance(PyObject* self, PyObject* args) {
    PyObject* list_obj;
    if (!PyArg_ParseTuple(args, "O", &list_obj)) {
        return NULL;
    }

    Py_ssize_t n = PyList_Size(list_obj);
    if (n <= 1) {
        return PyFloat_FromDouble(0.0);
    }

    double sum = 0.0;
    double sum_sq = 0.0;

    for (Py_ssize_t i = 0; i < n; i++) {
        PyObject* item = PyList_GetItem(list_obj, i);
        double val = PyFloat_AsDouble(item);
        sum += val;
        sum_sq += val * val;
    }

    double mean = sum / n;
    double var = (sum_sq / n) - (mean * mean);

    return PyFloat_FromDouble(var);
}

static PyMethodDef StatUtilsMethods[] = {
    {"variance", variance, METH_VARARGS, "Calculate variance."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef statutilsmodule = {
    PyModuleDef_HEAD_INIT,
    "libstatutils",
    NULL,
    -1,
    StatUtilsMethods
};

PyMODINIT_FUNC PyInit_libstatutils(void) {
    return PyModule_Create(&statutilsmodule);
}
EOF

    cat << 'EOF' > /app/libstatutils-1.2.0/setup.py
from setuptools import setup, Extension
import os

cflags = os.environ.get("CFLAGS", "").split()

module = Extension('libstatutils',
                   sources=['statutils.c'],
                   extra_compile_args=cflags)

setup(name='libstatutils',
      version='1.2.0',
      ext_modules=[module])
EOF

    cat << 'EOF' > /app/libstatutils-1.2.0/Makefile
CFLAGS = -O3 -ffast-math

install_python:
	CFLAGS="$(CFLAGS)" pip3 install .
EOF

    mkdir -p /app/corpora/clean /app/corpora/evil

    python3 -c "
import os, random
for i in range(5):
    with open(f'/app/corpora/clean/trace_{i}.csv', 'w') as f:
        for _ in range(100): f.write(f'{random.gauss(0, 1)}\n')
for i in range(5):
    with open(f'/app/corpora/evil/trace_{i}.csv', 'w') as f:
        for _ in range(100): f.write(f'{random.gauss(100000000, 0.01)}\n')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
