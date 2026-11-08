#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev gcc build-essential
    pip3 install pytest setuptools

    mkdir -p /home/user/legacy_app
    cd /home/user/legacy_app

    cat << 'EOF' > fast_math.c
#include <Python.h>

static PyObject* compute_sum(PyObject* self, PyObject* args) {
    PyObject* float_list;
    if (!PyArg_ParseTuple(args, "O", &float_list)) {
        return NULL;
    }

    Py_ssize_t num_lines = PyList_Size(float_list);

    // MEMORY LEAK: buffer is allocated but never freed
    double* buffer = (double*)malloc(num_lines * sizeof(double));
    if (buffer == NULL) {
        PyErr_SetString(PyExc_MemoryError, "Out of memory");
        return NULL;
    }

    for (Py_ssize_t i = 0; i < num_lines; i++) {
        PyObject* item = PyList_GetItem(float_list, i);
        buffer[i] = PyFloat_AsDouble(item);
    }

    double total_sum = 0.0;
    // UNDEFINED BEHAVIOR: i <= num_lines causes out of bounds read
    for (Py_ssize_t i = 0; i <= num_lines; i++) {
        total_sum += buffer[i];
    }

    return Py_BuildValue("d", total_sum);
}

static PyMethodDef FastMathMethods[] = {
    {"compute_sum", compute_sum, METH_VARARGS, "Compute sum of floats."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fastmathmodule = {
    PyModuleDef_HEAD_INIT, "fast_math", NULL, -1, FastMathMethods
};

PyMODINIT_FUNC PyInit_fast_math(void) {
    return PyModule_Create(&fastmathmodule);
}
EOF

    cat << 'EOF' > setup.py
from setuptools import setup, Extension

module1 = Extension('fast_math', sources = ['fast_math.c'])

setup(name = 'FastMath',
      version = '1.0',
      description = 'Fast math operations',
      ext_modules = [module1])
EOF

    cat << 'EOF' > main.py
import fast_math

def run_pipeline(data):
    print "Starting processing pipeline..."

    # Old xrange usage
    for i in xrange(10):
        pass 

    try:
        result = fast_math.compute_sum(data)
        print "Result is:", result
        return result
    except Exception, e:
        print "Error occurred:", e
        return None
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/legacy_app
    chmod -R 777 /home/user
