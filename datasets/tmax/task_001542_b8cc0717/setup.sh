#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev python3-setuptools
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create the C-extension source
    cat << 'EOF' > fast_math.c
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <math.h>

static PyObject* fast_math_calc(PyObject* self, PyObject* args) {
    double x, y;
    if (!PyArg_ParseTuple(args, "dd", &x, &y)) {
        return NULL;
    }
    // Causes NaN if x < y
    double result = sqrt(x - y);
    return PyFloat_FromDouble(result);
}

static PyMethodDef FastMathMethods[] = {
    {"calc", fast_math_calc, METH_VARARGS, "Calculate risk."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fastmathmodule = {
    PyModuleDef_HEAD_INIT,
    "fast_math",
    NULL,
    -1,
    FastMathMethods
};

PyMODINIT_FUNC PyInit_fast_math(void) {
    return PyModule_Create(&fastmathmodule);
}
EOF

    # Create the broken setup.py (missing libraries)
    cat << 'EOF' > setup.py
from setuptools import setup, Extension

module1 = Extension('fast_math',
                    sources = ['fast_math.c'])

setup (name = 'FastMath',
       version = '1.0',
       description = 'This is a math package',
       ext_modules = [module1])
EOF

    # Create the Python script
    cat << 'EOF' > process_data.py
import sys
import csv
import fast_math
import math

def run(start, end):
    with open('/home/user/data.csv', 'r') as f:
        reader = csv.reader(f)
        rows = list(reader)

    for i in range(start, end):
        x, y = map(float, rows[i])
        res = fast_math.calc(x, y)
        if math.isnan(res):
            raise ValueError("Numerical instability detected in batch!")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python process_data.py <start_idx> <end_idx>")
        sys.exit(1)
    run(int(sys.argv[1]), int(sys.argv[2]))
EOF

    # Create the dataset
    python3 -c "
import random
random.seed(42)
with open('data.csv', 'w') as f:
    for i in range(1000):
        if i == 682:
            f.write('10.0,10.0001\n') # The failing row (x < y causes negative sqrt)
        else:
            x = random.uniform(20.0, 100.0)
            y = random.uniform(1.0, 19.0)
            f.write(f'{x},{y}\n')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
