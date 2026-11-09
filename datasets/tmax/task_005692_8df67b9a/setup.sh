#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev gcc build-essential curl
    pip3 install pytest flask setuptools

    mkdir -p /home/user/workspace/token_api/src
    mkdir -p /home/user/workspace/token_api/lib

    cat << 'EOF' > /home/user/workspace/token_api/src/core_algo.c
int secure_transform(int seed) {
    // A dummy numerical "secure" transformation
    long long result = seed;
    for(int i=0; i<1000; i++) {
        result = (result * 13 + 17) % 9973;
    }
    return (int)result;
}
EOF

    cat << 'EOF' > /home/user/workspace/token_api/src/token_ext.c
#define PY_SSIZE_T_CLEAN
#include <Python.h>

// Declare the external function
extern int secure_transform(int);

static PyObject* py_generate_token(PyObject* self, PyObject* args) {
    int seed;
    if (!PyArg_ParseTuple(args, "i", &seed)) {
        return NULL;
    }
    int token = secure_transform(seed);
    return PyLong_FromLong(token);
}

static PyMethodDef TokenMethods[] = {
    {"generate_token", py_generate_token, METH_VARARGS, "Generate a secure token from a seed."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef tokenmodule = {
    PyModuleDef_HEAD_INIT,
    "token_ext",
    NULL,
    -1,
    TokenMethods
};

PyMODINIT_FUNC PyInit_token_ext(void) {
    return PyModule_Create(&tokenmodule);
}
EOF

    cat << 'EOF' > /home/user/workspace/token_api/setup.py
from setuptools import setup, Extension
import os

# BROKEN SETUP: missing libraries, library_dirs, and runtime_library_dirs
token_module = Extension(
    'token_ext',
    sources=['src/token_ext.c']
)

setup(
    name='token_api_core',
    version='1.0',
    description='Token Extension',
    ext_modules=[token_module]
)
EOF

    cat << 'EOF' > /home/user/workspace/token_api/app.py
from flask import Flask, request, jsonify
import token_ext

app = Flask(__name__)

@app.route('/generate', methods=['GET'])
def generate():
    seed = request.args.get('seed', default=0, type=int)
    token = token_ext.generate_token(seed)
    return jsonify({"status": "success", "seed": seed, "token": token})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
