#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        python3-dev \
        build-essential \
        ffmpeg \
        espeak

    pip3 install pytest

    mkdir -p /home/user/release_prep/fast_dsp/src
    cat << 'EOF' > /home/user/release_prep/fast_dsp/setup.py
from setuptools import setup, Extension
# BROKEN: missing comma and wrong source file
module1 = Extension('fast_dsp',
                    sources = ['src/processor.c' 'src/missing.c'])

setup (name = 'fast_dsp',
       version = '1.0',
       description = 'Broken package',
       ext_modules = [module1])
EOF

    cat << 'EOF' > /home/user/release_prep/fast_dsp/src/processor.c
#include <Python.h>

static PyObject* sort_and_merge(PyObject* self, PyObject* args) {
    PyObject *listObj;
    if (!PyArg_ParseTuple(args, "O", &listObj)) return NULL;

    Py_ssize_t size = PyList_Size(listObj);
    long arr[10]; // BUG: Hardcoded size 10, out of bounds if size > 10

    for (Py_ssize_t i = 0; i < size; i++) {
        PyObject *temp = PyList_GetItem(listObj, i);
        arr[i] = PyLong_AsLong(temp);
    }

    // Inefficient Bubble Sort
    for (int i = 0; i < size - 1; i++) {
        for (int j = 0; j < size - i - 1; j++) {
            if (arr[j] > arr[j+1]) {
                long temp = arr[j];
                arr[j] = arr[j+1];
                arr[j+1] = temp;
            }
        }
    }

    PyObject *outList = PyList_New(size);
    for (Py_ssize_t i = 0; i < size; i++) {
        PyList_SetItem(outList, i, PyLong_FromLong(arr[i]));
    }
    return outList;
}

static PyMethodDef FastMethods[] = {
    {"sort_and_merge",  sort_and_merge, METH_VARARGS, "Sort an array."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fastmodule = {
    PyModuleDef_HEAD_INIT, "fast_dsp", NULL, -1, FastMethods
};

PyMODINIT_FUNC PyInit_fast_dsp(void) {
    return PyModule_Create(&fastmodule);
}
EOF

    mkdir -p /app
    espeak -s 120 -w /app/transmission.wav "42, 17, 8, 99, 23, 4, 16, 55, 88, 1"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
