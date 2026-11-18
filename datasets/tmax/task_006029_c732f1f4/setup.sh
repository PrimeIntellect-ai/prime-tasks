#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev gcc
    pip3 install pytest wheel setuptools

    mkdir -p /home/user/polymath/data
    mkdir -p /home/user/polymath/src

    cat << 'EOF' > /home/user/polymath/data/matrix.json
{
  "M00": 1,
  "M01": 1,
  "M10": 1,
  "M11": 0,
  "MODULUS": 1000000007
}
EOF

    cat << 'EOF' > /home/user/polymath/src/fib.c
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include "constants.h"

// Simple function to compute Nth fib via fast matrix exp
static PyObject* fib(PyObject* self, PyObject* args) {
    long long n;
    if (!PyArg_ParseTuple(args, "L", &n))
        return NULL;

    long long a = M00, b = M01, c = M10, d = M11; // 1, 1, 1, 0
    long long rc = 0, rd = 1; // base cases for fib: F(0)=0, F(1)=1

    while (n > 0) {
        if (n % 2 == 1) {
            long long tc = (a * rc + b * rd) % MODULUS;
            long long td = (c * rc + d * rd) % MODULUS;
            rc = tc; rd = td;
        }
        long long ta = (a * a + b * c) % MODULUS;
        long long tb = (a * b + b * d) % MODULUS;
        long long tc = (c * a + d * c) % MODULUS;
        long long td = (c * b + d * d) % MODULUS;
        a = ta; b = tb; c = tc; d = td;
        n /= 2;
    }
    return PyLong_FromLongLong(rc);
}

static PyMethodDef FibMethods[] = {
    {"fib",  fib, METH_VARARGS, "Compute nth Fibonacci number."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fibmodule = {
    PyModuleDef_HEAD_INIT,
    "fib_ext",
    NULL,
    -1,
    FibMethods
};

PyMODINIT_FUNC PyInit_fib_ext(void) {
    return PyModule_Create(&fibmodule);
}
EOF

    cat << 'EOF' > /home/user/polymath/setup.py
from setuptools import setup, Extension

# FIXME: Define the Extension correctly
# ext_modules = ...

setup(
    name='polymath',
    version='0.1.0',
    description='Fast math package',
    # ext_modules=ext_modules
)
EOF

    cat << 'EOF' > /home/user/polymath/ci_build.sh
#!/bin/bash

# Add your pipeline steps here
EOF
    chmod +x /home/user/polymath/ci_build.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
