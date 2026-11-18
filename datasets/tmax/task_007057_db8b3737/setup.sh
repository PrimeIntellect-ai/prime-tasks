#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev gcc
    pip3 install pytest hypothesis setuptools

    mkdir -p /home/user/fastsum_project
    cd /home/user/fastsum_project

    cat << 'EOF' > fastsum.c
#define PY_SSIZE_T_CLEAN
#include <Python.h>

static PyObject* solve(PyObject* self, PyObject* args) {
    PyObject* list_obj;
    int target;
    if (!PyArg_ParseTuple(args, "Oi", &list_obj, &target)) {
        return NULL;
    }

    Py_ssize_t size = PyList_Size(list_obj);
    int* arr = (int*)malloc(size * sizeof(int));
    for (Py_ssize_t i = 0; i < size; i++) {
        PyObject* item = PyList_GetItem(list_obj, i);
        arr[i] = (int)PyLong_AsLong(item);
    }

    // Simple recursive subset sum
    int* result_indices = (int*)malloc(size * sizeof(int));
    int result_count = 0;

    // DP or recursive search. For small sizes (<=20), bitmask is fine.
    int found = 0;
    long long max_mask = 1LL << size;
    for (long long mask = 0; mask < max_mask; mask++) {
        long long current_sum = 0;
        for (Py_ssize_t i = 0; i < size; i++) {
            if ((mask >> i) & 1) {
                current_sum += arr[i];
            }
        }
        if (current_sum == target) {
            for (Py_ssize_t i = 0; i < size; i++) {
                if ((mask >> i) & 1) {
                    result_indices[result_count++] = i;
                }
            }
            found = 1;
            break;
        }
    }

    free(arr);

    if (!found) {
        free(result_indices);
        Py_RETURN_NONE;
    }

    PyObject* py_result = PyList_New(result_count);
    for (int i = 0; i < result_count; i++) {
        PyList_SetItem(py_result, i, PyLong_FromLong(result_indices[i]));
    }
    free(result_indices);
    return py_result;
}

static PyMethodDef FastSumMethods[] = {
    {"solve",  solve, METH_VARARGS, "Solve subset sum."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fastsummodule = {
    PyModuleDef_HEAD_INIT,
    "fastsum",
    NULL,
    -1,
    FastSumMethods
};

PyMODINIT_FUNC PyInit_fastsum(void) {
    return PyModule_Create(&fastsummodule);
}
EOF

    cat << 'EOF' > setup.py
from setuptools import setup, Extension

# BROKEN: The source file is wrong
fastsum_ext = Extension('fastsum', sources=['wrong_source.c'])

setup(
    name='fastsum',
    version='1.0',
    description='Fast constraint solver',
    ext_modules=[fastsum_ext]
)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
