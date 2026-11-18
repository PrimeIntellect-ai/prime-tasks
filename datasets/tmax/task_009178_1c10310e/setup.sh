#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential python3-setuptools
pip3 install pytest

mkdir -p /home/user/project/data_a
mkdir -p /home/user/project/data_b

# Create test data
echo -n "hello world" > /home/user/project/data_a/file1.txt
echo -n "hello world" > /home/user/project/data_b/file1.txt

echo -n "test data A" > /home/user/project/data_a/file2.txt
echo -n "test data B" > /home/user/project/data_b/file2.txt

echo -n "identical content" > /home/user/project/data_a/file3.txt
echo -n "identical content" > /home/user/project/data_b/file3.txt

# Create broken adler32.c
cat << 'EOF' > /home/user/project/adler32.c
#define PY_SSIZE_T_CLEAN
#include <Python.h>

static PyObject* adler32_checksum(PyObject* self, PyObject* args) {
    const unsigned char *data;
    Py_ssize_t len;

    if (!PyArg_ParseTuple(args, "y#", &data, &len)) {
        return NULL;
    }

    uint32_t a = 1, b = 0;
    // BUG: MOD_ADLER should be 65521
    const uint32_t MOD_ADLER = 65536; 

    for (Py_ssize_t i = 0; i < len; ++i) {
        a = (a + data[i]) % MOD_ADLER;
        b = (b + a) % MOD_ADLER;
    }

    uint32_t checksum = (b << 16) | a;
    return PyLong_FromUnsignedLong(checksum);
}

static PyMethodDef Adler32Methods[] = {
    {"checksum",  adler32_checksum, METH_VARARGS, "Calculate adler32 checksum."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef adler32module = {
    PyModuleDef_HEAD_INIT,
    "adler32_fast",
    NULL,
    -1,
    Adler32Methods
};

PyMODINIT_FUNC PyInit_adler32_fast(void) {
    return PyModule_Create(&adler32module);
}
EOF

# Create broken setup.py
cat << 'EOF' > /home/user/project/setup.py
from setuptools import setup, Extension

module1 = Extension('adler32_fast',
                    sources = ['wrong_file.c'])

setup (name = 'adler32_fast',
       version = '1.0',
       description = 'Fast adler32',
       ext_modules = [module1])
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
