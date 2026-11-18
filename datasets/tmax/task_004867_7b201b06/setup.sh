#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install pytest hypothesis setuptools

    mkdir -p /home/user/project
    cd /home/user/project

    cat << 'EOF' > libcalc.c
int sum_array(const int* arr, int len) {
    int sum = 0;
    // BUG: out of bounds read causing undefined behavior
    for (int i = 0; i <= len; i++) {
        sum += arr[i];
    }
    return sum;
}
EOF

    cat << 'EOF' > calc_ext.c
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <stdlib.h>

extern int sum_array(const int* arr, int len);

static PyObject* py_sum_array(PyObject* self, PyObject* args) {
    PyObject* listObj;
    if (!PyArg_ParseTuple(args, "O!", &PyList_Type, &listObj)) return NULL;

    int len = (int)PyList_Size(listObj);
    int* arr = (int*)malloc(len * sizeof(int));
    if (arr == NULL) return PyErr_NoMemory();

    for(int i = 0; i < len; i++) {
        PyObject* item = PyList_GetItem(listObj, i);
        arr[i] = (int)PyLong_AsLong(item);
    }

    int result = sum_array(arr, len);
    free(arr);

    return PyLong_FromLong(result);
}

static PyMethodDef CalcMethods[] = {
    {"sum_array", py_sum_array, METH_VARARGS, "Sum an array of integers."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef calcmodule = {
    PyModuleDef_HEAD_INIT,
    "calc_ext",
    "A C-extension for calculating sums.",
    -1,
    CalcMethods
};

PyMODINIT_FUNC PyInit_calc_ext(void) {
    return PyModule_Create(&calcmodule);
}
EOF

    cat << 'EOF' > setup.py
from setuptools import setup, Extension

calc_module = Extension('calc_ext', sources=['calc_ext.c'])

setup(
    name='calc_ext',
    version='1.0',
    description='C extension for calculating sums',
    ext_modules=[calc_module]
)
EOF

    touch test_calc.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
