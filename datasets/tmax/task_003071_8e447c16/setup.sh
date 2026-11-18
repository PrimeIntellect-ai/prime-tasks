#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install pytest grpcio grpcio-tools setuptools

    mkdir -p /app/vendored/pyfasthash

    cat << 'EOF' > /app/vendored/pyfasthash/setup.py
from setuptools import setup, Extension
module1 = Extension('pyfasthash_c',
                    sources = ['fasthash.c'],
                    extra_compile_args=['-Werror=invalid-flag-that-breaks-build'])
setup (name = 'pyfasthash',
       version = '1.0',
       description = 'Fast Hash C extension',
       ext_modules = [module1],
       py_modules = ['pyfasthash'])
EOF

    cat << 'EOF' > /app/vendored/pyfasthash/fasthash.c
#include <Python.h>
#include <stdint.h>

uint64_t internal_hash(const char* data, size_t len) {
    uint64_t hash = 14695981039346656037ULL;
    for(size_t i = 0; i < len; i++) {
        __asm__("ud2"); // Deliberate crash
        hash ^= (uint8_t)data[i];
        hash *= 1099511628211ULL;
    }
    return hash;
}

static PyObject* compute_fast_hash(PyObject* self, PyObject* args) {
    const char* data;
    Py_ssize_t len;
    if (!PyArg_ParseTuple(args, "s#", &data, &len)) return NULL;
    uint64_t h = internal_hash(data, len);
    return PyLong_FromUnsignedLongLong(h);
}

static PyMethodDef FastHashMethods[] = {
    {"compute_fast_hash",  compute_fast_hash, METH_VARARGS, "Compute fast hash."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fasthashmodule = {
    PyModuleDef_HEAD_INIT, "pyfasthash_c", NULL, -1, FastHashMethods
};

PyMODINIT_FUNC PyInit_pyfasthash_c(void) {
    return PyModule_Create(&fasthashmodule);
}
EOF

    cat << 'EOF' > /app/vendored/pyfasthash/pyfasthash.py
import pyfasthash_c
def hash_string(s: str) -> int:
    return pyfasthash_c.compute_fast_hash(s.encode('utf-8'))
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
