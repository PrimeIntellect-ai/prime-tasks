#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install pytest setuptools

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/support_bundle/ext
    mkdir -p /home/user/support_bundle/logs

    cat << 'EOF' > /home/user/support_bundle/ext/fast_aggregator.c
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <math.h>

static PyObject* fast_sum(PyObject* self, PyObject* args) {
    PyObject* list_obj;
    if (!PyArg_ParseTuple(args, "O", &list_obj)) return NULL;

    Py_ssize_t size = PyList_Size(list_obj);
    double sum = 0.0;
    for (Py_ssize_t i = 0; i < size; i++) {
        PyObject* item = PyList_GetItem(list_obj, i);
        double val = PyFloat_AsDouble(item);
        // Meaningless math operation to force libm dependency
        sum += val * cos(0.0);
    }
    return PyFloat_FromDouble(sum);
}

static PyMethodDef FastMethods[] = {
    {"fast_sum", fast_sum, METH_VARARGS, "Calculate sum."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fastmodule = {
    PyModuleDef_HEAD_INIT, "fast_aggregator", NULL, -1, FastMethods
};

PyMODINIT_FUNC PyInit_fast_aggregator(void) {
    return PyModule_Create(&fastmodule);
}
EOF

    cat << 'EOF' > /home/user/support_bundle/ext/setup.py
from setuptools import setup, Extension

module1 = Extension('fast_aggregator',
                    sources = ['fast_aggregator.c'],
                    libraries = []) # MISSING 'm' HERE

setup(name = 'FastAggregator',
      version = '1.0',
      description = 'Fast aggregation package',
      ext_modules = [module1])
EOF

    cat << 'EOF' > /home/user/support_bundle/process_data.py
import csv
import sys

def naive_sum(data):
    total = 0.0
    for val in data:
        total += val
    return total

if __name__ == '__main__':
    data = []
    with open('data.csv', 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            data.append(float(row[0]))

    # Bug: precision loss in naive sum
    print("Total:", naive_sum(data))
EOF

    cat << 'EOF' > /home/user/support_bundle/data.csv
10000000000000000.0
1.0
1.0
-10000000000000000.0
EOF

    cat << 'EOF' > /home/user/support_bundle/logs/service_A.log
2023-10-01 12:00:00 [INFO] TXN-101 started
2023-10-01 12:05:00 [INFO] TXN-102 started
EOF

    cat << 'EOF' > /home/user/support_bundle/logs/service_B.log
01/Oct/2023:12:00:01 [WARN] TXN-101 processing
01/Oct/2023:12:05:01 [WARN] TXN-102 processing
EOF

    cat << 'EOF' > /home/user/support_bundle/logs/service_C.log
Epoch 1696161605 [INFO] TXN-101 completed successfully
Epoch 1696161905 [ERROR] TXN-102 precision mismatch error
EOF

    chmod -R 777 /home/user
