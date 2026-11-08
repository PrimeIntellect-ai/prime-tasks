#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install pytest setuptools

    mkdir -p /home/user/math_app
    cd /home/user/math_app

    # 1. Create the C extension
    cat << 'EOF' > mathcore.c
#include <Python.h>
#include <math.h>

static PyObject* fast_sqrt(PyObject* self, PyObject* args) {
    double input;
    if (!PyArg_ParseTuple(args, "d", &input)) {
        return NULL;
    }
    double result = sqrt(input);
    return Py_BuildValue("d", result);
}

static PyMethodDef MathCoreMethods[] = {
    {"fast_sqrt", fast_sqrt, METH_VARARGS, "Calculate square root."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef mathcoremodule = {
    PyModuleDef_HEAD_INIT, "mathcore", NULL, -1, MathCoreMethods
};

PyMODINIT_FUNC PyInit_mathcore(void) {
    return PyModule_Create(&mathcoremodule);
}
EOF

    # 2. Create the broken setup.py (missing libraries=['m'])
    cat << 'EOF' > setup.py
from setuptools import setup, Extension

module1 = Extension('mathcore',
                    sources = ['mathcore.c'])

setup (name = 'MathCore',
       version = '1.0',
       description = 'This is a math package',
       ext_modules = [module1])
EOF

    # 3. Create the initial database with legacy data
    cat << 'EOF' > init_db.py
import sqlite3

conn = sqlite3.connect('/home/user/math_app/data.db')
c = conn.cursor()
c.execute('CREATE TABLE calculations (id INTEGER, result REAL)')
c.execute('INSERT INTO calculations VALUES (1, 3.14)')
c.execute('INSERT INTO calculations VALUES (2, 2.71)')
conn.commit()
conn.close()
EOF
    python3 init_db.py
    rm init_db.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
