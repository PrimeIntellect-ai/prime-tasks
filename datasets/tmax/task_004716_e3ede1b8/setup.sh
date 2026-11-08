#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc python3-dev
pip3 install pytest

mkdir -p /home/user/math_service

cat << 'EOF' > /home/user/math_service/algo.c
#include <Python.h>
#include <math.h>

static PyObject* compute(PyObject* self, PyObject* args) {
    int n;
    double x;
    if (!PyArg_ParseTuple(args, "id", &n, &x)) {
        return NULL;
    }

    double result = 0.0;
    for (int i = 1; i <= n; i++) {
        result += pow(x, i) / i;
    }

    return PyFloat_FromDouble(result);
}

static PyMethodDef AlgoMethods[] = {
    {"compute", compute, METH_VARARGS, "Compute the series."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef algomodule = {
    PyModuleDef_HEAD_INIT,
    "algo_ext",
    NULL,
    -1,
    AlgoMethods
};

PyMODINIT_FUNC PyInit_algo_ext(void) {
    return PyModule_Create(&algomodule);
}
EOF

cat << 'EOF' > /home/user/math_service/setup.py
from setuptools import setup, Extension

module1 = Extension('algo_ext',
                    sources = ['algo.c'])

setup (name = 'algo_ext',
       version = '1.0',
       description = 'Numerical algorithm package',
       ext_modules = [module1])
EOF

cat << 'EOF' > /home/user/math_service/requirements.txt
grpcio==1.60.0
grpcio-tools==1.60.0
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
