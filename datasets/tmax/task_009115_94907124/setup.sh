#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev gcc
    pip3 install pytest pytest-asyncio hypothesis websockets setuptools

    mkdir -p /home/user/app/lib /home/user/app/ext /home/user/app/db

    # Create dummy custom shared library
    cat << 'EOF' > /tmp/customsec.c
#include <string.h>
#include <stdio.h>

void custom_hash(const char* input, char* output) {
    sprintf(output, "%s_hashed", input);
}
EOF
    gcc -shared -fPIC -o /home/user/app/lib/libcustomsec.so /tmp/customsec.c

    # Create Python C-extension
    cat << 'EOF' > /home/user/app/ext/sec_ext.c
#define PY_SSIZE_T_CLEAN
#include <Python.h>

void custom_hash(const char* input, char* output);

static PyObject* compute_hash(PyObject* self, PyObject* args) {
    const char* input;
    if (!PyArg_ParseTuple(args, "s", &input)) {
        return NULL;
    }
    char output[1024];
    custom_hash(input, output);
    return Py_BuildValue("s", output);
}

static PyMethodDef SecMethods[] = {
    {"compute_hash",  compute_hash, METH_VARARGS, "Compute hash."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef secmodule = {
    PyModuleDef_HEAD_INIT,
    "sec_ext",
    NULL,
    -1,
    SecMethods
};

PyMODINIT_FUNC PyInit_sec_ext(void) {
    return PyModule_Create(&secmodule);
}
EOF

    # Create setup.py without rpath
    cat << 'EOF' > /home/user/app/ext/setup.py
from setuptools import setup, Extension

module1 = Extension('sec_ext',
                    sources = ['sec_ext.c'],
                    libraries = ['customsec'],
                    library_dirs = ['/home/user/app/lib'])

setup (name = 'sec_ext',
       version = '1.0',
       description = 'Security extension',
       ext_modules = [module1])
EOF

    # Create dummy database
    python3 -c "
import sqlite3
import os

conn = sqlite3.connect('/home/user/app/db/chat.db')
c = conn.cursor()
c.execute('CREATE TABLE messages (id INTEGER PRIMARY KEY, content TEXT)')
c.execute('INSERT INTO messages (content) VALUES (\"Hello world\")')
c.execute('INSERT INTO messages (content) VALUES (\"Secure message\")')
conn.commit()
conn.close()
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
