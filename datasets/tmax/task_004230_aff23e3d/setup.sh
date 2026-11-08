#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential golang-go
    pip3 install pytest setuptools

    mkdir -p /app/vendored/artifact_parser-1.2.0/src
    mkdir -p /app/build_tool/cmd
    mkdir -p /app/build_tool/core
    mkdir -p /opt/oracle

    cat << 'EOF' > /app/vendored/artifact_parser-1.2.0/setup.py
from setuptools import setup, Extension

module1 = Extension('artifact_parser',
                    sources = ['src/parser.c'])

setup (name = 'artifact_parser',
       version = '1.2.0',
       description = 'Artifact parser',
       ext_modules = [module1])
EOF

    cat << 'EOF' > /app/vendored/artifact_parser-1.2.0/src/parser.c
#define PY_SSIZE_T_CLEAN
#include <Python.h>

static PyObject* parse_manifest(PyObject* self, PyObject* args) {
    const char* data;
    Py_ssize_t total_size;

    if (!PyArg_ParseTuple(args, "y#", &data, &total_size)) {
        return NULL;
    }

    if (total_size < 4) {
        PyErr_SetString(PyExc_ValueError, "Buffer too small for count");
        return NULL;
    }

    int count = *(int*)data;
    Py_ssize_t offset = 4;

    PyObject* list = PyList_New(0);

    for (int i = 0; i < count; i++) {
        if (offset + 4 > total_size) {
            PyErr_SetString(PyExc_ValueError, "Buffer too small for length");
            Py_DECREF(list);
            return NULL;
        }
        int name_len = *(int*)(data + offset);
        offset += 4;

        // VULNERABILITY: Missing bounds check
        // if (offset + name_len > total_size) { ... }

        PyObject* str = PyUnicode_DecodeUTF8(data + offset, name_len, "strict");
        if (!str) {
            Py_DECREF(list);
            return NULL;
        }
        PyList_Append(list, str);
        Py_DECREF(str);
        offset += name_len;
    }

    return list;
}

static PyMethodDef ArtifactParserMethods[] = {
    {"parse_manifest",  parse_manifest, METH_VARARGS, "Parse artifact manifest."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef artifactparsermodule = {
    PyModuleDef_HEAD_INIT,
    "artifact_parser",
    NULL,
    -1,
    ArtifactParserMethods
};

PyMODINIT_FUNC PyInit_artifact_parser(void) {
    return PyModule_Create(&artifactparsermodule);
}
EOF

    cat << 'EOF' > /app/build_tool/go.mod
module build_tool

go 1.18
EOF

    cat << 'EOF' > /app/build_tool/main.go
package main

import "build_tool/cmd"

func main() {
    cmd.Execute()
}
EOF

    cat << 'EOF' > /app/build_tool/cmd/cmd.go
package cmd

import "build_tool/core"
import "fmt"

func Execute() {
    fmt.Println(core.GetMessage())
}
EOF

    cat << 'EOF' > /app/build_tool/core/core.go
package core

import "build_tool/cmd"

func GetMessage() string {
    return "Hello"
}
EOF

    cat << 'EOF' > /opt/oracle/process_artifacts_oracle.py
import sys
import json
import struct

def parse(data):
    if len(data) < 4:
        raise ValueError()
    count = struct.unpack('i', data[:4])[0]
    offset = 4
    names = []
    for _ in range(count):
        if offset + 4 > len(data):
            raise ValueError()
        name_len = struct.unpack('i', data[offset:offset+4])[0]
        offset += 4
        if offset + name_len > len(data) or name_len < 0:
            raise ValueError()
        try:
            name = data[offset:offset+name_len].decode('utf-8')
        except UnicodeDecodeError:
            raise ValueError()
        names.append(name)
        offset += name_len
    return names

def main():
    if len(sys.argv) < 2:
        return
    try:
        with open(sys.argv[1], 'rb') as f:
            data = f.read()
        names = parse(data)
        names.sort()
        print(json.dumps(names))
    except Exception:
        print('["ERROR"]')

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
