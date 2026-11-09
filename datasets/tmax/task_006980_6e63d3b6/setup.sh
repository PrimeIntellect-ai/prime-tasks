#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install pytest setuptools

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/telemetry
    cd /home/user/telemetry

    cat << 'EOF' > lz_utils.h
#ifndef LZ_UTILS_H
#define LZ_UTILS_H
char* fake_decompress(const char* input);
#endif
EOF

    cat << 'EOF' > lz_utils.c
#include "lz_utils.h"
#include <stdlib.h>
#include <string.h>

char* fake_decompress(const char* input) {
    // Just a mock that returns a hardcoded string of log lines
    const char* logs = "2023-10-01T12:00:00|INFO|System started\n"
                       "2023-10-01T12:05:00|WARNING|Disk space low\n"
                       "2023-10-01T12:10:00|ERROR|Parsing failed on | symbol in message\n"
                       "2023-10-01T12:15:00|INFO|System shutting down\n";
    char* output = malloc(strlen(logs) + 1);
    strcpy(output, logs);
    return output;
}
EOF

    cat << 'EOF' > fast_decomp.c
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include "lz_utils.h"

static PyObject* decomp_read_all(PyObject* self, PyObject* args) {
    const char* input_path;
    if (!PyArg_ParseTuple(args, "s", &input_path)) {
        return NULL;
    }

    char* decompressed = fake_decompress(input_path);
    if (!decompressed) {
        PyErr_SetString(PyExc_RuntimeError, "Decompression failed");
        return NULL;
    }

    PyObject* result = PyUnicode_FromString(decompressed);
    free(decompressed);
    return result;
}

static PyMethodDef FastDecompMethods[] = {
    {"read_all", decomp_read_all, METH_VARARGS, "Read and decompress data."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fastdecompmodule = {
    PyModuleDef_HEAD_INIT,
    "fast_decomp",
    NULL,
    -1,
    FastDecompMethods
};

PyMODINIT_FUNC PyInit_fast_decomp(void) {
    return PyModule_Create(&fastdecompmodule);
}
EOF

    cat << 'EOF' > setup.py
from setuptools import setup, Extension

module1 = Extension('fast_decomp',
                    sources = ['fast_decomp.c'])

setup (name = 'FastDecomp',
       version = '1.0',
       description = 'Fast decompression package',
       ext_modules = [module1])
EOF

    cat << 'EOF' > parser.py
import sys
import json
import fast_decomp

def main():
    if len(sys.argv) != 3:
        print("Usage: parser.py <input> <output>")
        sys.exit(1)

    in_file = sys.argv[1]
    out_file = sys.argv[2]

    raw_text = fast_decomp.read_all(in_file)

    records = []
    for line in raw_text.strip().split('\n'):
        if not line:
            continue
        # BUG: unpacking fails if message contains '|'
        ts, lvl, msg = line.split('|') 
        records.append({"timestamp": ts, "level": lvl, "message": msg})

    with open(out_file, 'w') as f:
        json.dump(records, f, indent=2)

if __name__ == '__main__':
    main()
EOF

    touch raw_data.bin

    cat << 'EOF' > container.log
[2023-10-01 12:10:05] Container starting...
[2023-10-01 12:10:06] Running telemetry job...
Traceback (most recent call last):
  File "parser.py", line 20, in <module>
    main()
  File "parser.py", line 16, in main
    ts, lvl, msg = line.split('|')
ValueError: too many values to unpack (expected 3)
[2023-10-01 12:10:06] Container exited with code 1
EOF

    chown -R user:user /home/user/telemetry
    chmod -R 777 /home/user
