#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install pytest setuptools

    mkdir -p /home/user/release_prep/src
    cd /home/user/release_prep

    cat << 'EOF' > src/token_validator.c
#include <Python.h>
#include <math.h>

static PyObject* validate(PyObject* self, PyObject* args) {
    const char* token;
    if (!PyArg_ParseTuple(args, "s", &token)) {
        return NULL;
    }
    double dummy = pow(2.0, 3.0) + sqrt(16.0); // requires -lm
    return Py_BuildValue("i", 1);
}

static PyMethodDef ValidatorMethods[] = {
    {"validate", validate, METH_VARARGS, "Validate a token."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef validatormodule = {
    PyModuleDef_HEAD_INIT, "token_validator", NULL, -1, ValidatorMethods
};

PyMODINIT_FUNC PyInit_token_validator(void) {
    return PyModule_Create(&validatormodule);
}
EOF

    cat << 'EOF' > setup.py
from setuptools import setup, Extension

module1 = Extension('token_validator',
                    sources = ['src/token_validator.c'])
                    # missing math library linkage

setup (name = 'TokenValidator',
       version = '1.0',
       description = 'This is a demo package',
       ext_modules = [module1])
EOF

    cat << 'EOF' > src/app.py
import time

HISTORY = []

def process_request(token):
    # TODO: Implement rate limiting (max 5 per second)

    # Store history (currently leaks memory!)
    HISTORY.append(token)

    return True
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
