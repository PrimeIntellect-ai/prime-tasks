#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev gcc make
    pip3 install pytest numpy scipy setuptools

    mkdir -p /app/freq_optimizer-1.0/src
    cat << 'EOF' > /app/freq_optimizer-1.0/setup.py
from setuptools import setup, Extension
import subprocess
import os

class MakeBuild:
    def __init__(self):
        subprocess.check_call(['make'])

setup(
    name='freq_optimizer',
    version='1.0',
    packages=['freq_optimizer'],
    ext_modules=[Extension('freq_optimizer._core', sources=['src/core.c'])],
)
EOF

    mkdir -p /app/freq_optimizer-1.0/freq_optimizer
    cat << 'EOF' > /app/freq_optimizer-1.0/freq_optimizer/__init__.py
from ._core import denoise_c
import numpy as np

def denoise(signal):
    sig_arr = np.array(signal, dtype=np.float64)
    out = np.zeros_like(sig_arr)
    denoise_c(sig_arr, out, len(sig_arr))
    return out
EOF

    cat << 'EOF' > /app/freq_optimizer-1.0/src/core.c
#include <Python.h>
#include <numpy/arrayobject.h>
#include <math.h>

static PyObject* denoise_c(PyObject* self, PyObject* args) {
    PyArrayObject *in_array, *out_array;
    int length;
    if (!PyArg_ParseTuple(args, "O!O!i", &PyArray_Type, &in_array, &PyArray_Type, &out_array, &length)) {
        return NULL;
    }
    double *in_data = (double *)PyArray_DATA(in_array);
    double *out_data = (double *)PyArray_DATA(out_array);

    for (int i = 0; i < length; i++) {
        // Dummy non-linear transformation requiring math.h
        out_data[i] = in_data[i] * exp(-0.01 * fabs(in_data[i])); 
    }

    Py_RETURN_NONE;
}

static PyMethodDef CoreMethods[] = {
    {"denoise_c", denoise_c, METH_VARARGS, "Denoise signal"},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef coremodule = {
    PyModuleDef_HEAD_INIT,
    "_core",
    NULL,
    -1,
    CoreMethods
};

PyMODINIT_FUNC PyInit__core(void) {
    import_array();
    return PyModule_Create(&coremodule);
}
EOF

    cat << 'EOF' > /app/freq_optimizer-1.0/Makefile
# Deliberately missing math library link flag
all:
	gcc -shared -o freq_optimizer/_core.so -fPIC -I/usr/include/python3.10 -I/usr/local/lib/python3.10/dist-packages/numpy/core/include src/core.c
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
