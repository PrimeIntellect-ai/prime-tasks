#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential zlib1g-dev
    pip3 install pytest setuptools

    mkdir -p /app/libwalparse

    cat << 'EOF' > /app/libwalparse/walparse.h
#ifndef WALPARSE_H
#define WALPARSE_H
#include <Python.h>
#endif
EOF

    cat << 'EOF' > /app/libwalparse/wal_parse.c
#include "walparse.h"
#include <zlib.h>
#include <stdint.h>
#include <string.h>

#define MAX_REC_SIZE 1024

static PyObject* parse_wal(PyObject* self, PyObject* args) {
    const char* filename;
    if (!PyArg_ParseTuple(args, "s", &filename)) {
        return NULL;
    }

    gzFile f = gzopen(filename, "rb");
    if (!f) {
        PyErr_SetString(PyExc_IOError, "Cannot open file");
        return NULL;
    }

    char buffer[65536];
    int bytes_read = gzread(f, buffer, sizeof(buffer));
    gzclose(f);

    if (bytes_read <= 0) {
        return PyList_New(0);
    }

    PyObject* list = PyList_New(0);
    int offset = 0;

    while (offset < bytes_read) {
        if (offset + 4 > bytes_read) break;

        int32_t rec_len;
        memcpy(&rec_len, buffer + offset, 4);

        if (rec_len + 4 > MAX_REC_SIZE) {
            break;
        }

        if (offset + 4 + rec_len > bytes_read) break;

        if (rec_len > 0) {
            PyObject* py_str = PyBytes_FromStringAndSize(buffer + offset + 4, rec_len);
            PyList_Append(list, py_str);
            Py_DECREF(py_str);
        }

        offset += 4 + rec_len;

        // Infinite loop / segfault if rec_len is negative
    }

    return list;
}

static PyMethodDef WalParseMethods[] = {
    {"parse", parse_wal, METH_VARARGS, "Parse a WAL file."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef walparsemodule = {
    PyModuleDef_HEAD_INIT,
    "walparse",
    NULL,
    -1,
    WalParseMethods
};

PyMODINIT_FUNC PyInit_walparse(void) {
    return PyModule_Create(&walparsemodule);
}
EOF

    cat << 'EOF' > /app/libwalparse/setup.py
from setuptools import setup, Extension

module1 = Extension('walparse',
                    sources = ['wal_parse.c'],
                    libraries = [])

setup (name = 'libwalparse',
       version = '1.2.0',
       description = 'WAL parser',
       ext_modules = [module1])
EOF

    cat << 'EOF' > /tmp/gen_wal.py
import gzip
import struct

records = []
for i in range(100):
    payload = f"SECRET_PAYLOAD_{i}".encode()
    records.append(struct.pack("<i", len(payload)) + payload)
    if i % 20 == 0:
        # Inject corrupted record: rec_len = -16 (0xFFFFFFF0)
        records.append(struct.pack("<i", -16) + b"A"*16)

with gzip.open("/app/suspicious.wal", "wb") as f:
    f.write(b"".join(records))
EOF

    python3 /tmp/gen_wal.py
    rm /tmp/gen_wal.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
