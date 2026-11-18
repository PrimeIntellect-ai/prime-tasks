#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install pytest setuptools packaging

    mkdir -p /home/user/ci_pipeline/math_accel/math_accel

    cat << 'EOF' > /home/user/ci_pipeline/math_accel/setup.py
from setuptools import setup, Extension

module = Extension('math_accel.core',
                   sources=['core.c'])

setup(
    name='math_accel',
    version='1.2.1',
    description='Math accelerator',
    ext_modules=[module],
    packages=['math_accel']
)
EOF

    cat << 'EOF' > /home/user/ci_pipeline/math_accel/core.c
#include <Python.h>
#include <math.h>

static PyObject* fast_pow(PyObject* self, PyObject* args) {
    double base, exp;
    if (!PyArg_ParseTuple(args, "dd", &base, &exp))
        return NULL;
    double result = pow(base, exp);
    return Py_BuildValue("d", result);
}

static PyMethodDef CoreMethods[] = {
    {"fast_pow", fast_pow, METH_VARARGS, "Calculate power fast."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef coremodule = {
    PyModuleDef_HEAD_INIT, "core", NULL, -1, CoreMethods
};

PyMODINIT_FUNC PyInit_core(void) {
    return PyModule_Create(&coremodule);
}
EOF

    cat << 'EOF' > /home/user/ci_pipeline/math_accel/math_accel/__init__.py
__version__ = "1.2.1"
try:
    from .core import fast_pow
except ImportError:
    def fast_pow(base, exp):
        return base ** exp
EOF

    cat << 'EOF' > /home/user/ci_pipeline/benchmark.py
import sys
import time
sys.path.insert(0, '/home/user/ci_pipeline/math_accel')

try:
    from math_accel.core import fast_pow
    c_ext_loaded = True
except ImportError as e:
    print(f"Failed to load C extension: {e}")
    sys.exit(1)

def pure_py_pow(base, exp):
    return base ** exp

def run_bench():
    # Pure Py
    start = time.time()
    for _ in range(5000000):
        pure_py_pow(2.0, 10.0)
    py_time = time.time() - start

    # C Ext
    start = time.time()
    for _ in range(5000000):
        fast_pow(2.0, 10.0)
    c_time = time.time() - start

    with open('/home/user/ci_pipeline/benchmark_results.txt', 'w') as f:
        f.write(f"PurePython,{py_time:.6f}\n")
        f.write(f"CExtension,{c_time:.6f}\n")

if __name__ == '__main__':
    run_bench()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
