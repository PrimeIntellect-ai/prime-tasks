#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential make gcc
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/log_sanitizer
    mkdir -p /app/vendored/py-fast-log-parser
    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean

    # Create vendored package
    cat << 'EOF' > /app/vendored/py-fast-log-parser/setup.py
from setuptools import setup, Extension

module1 = Extension('fast_log_parser',
                    sources = ['fast_log_parser.c'])

setup (name = 'fast_log_parser',
       version = '1.0.0',
       description = 'Fast log parser',
       ext_modules = [module1])
EOF

    cat << 'EOF' > /app/vendored/py-fast-log-parser/fast_log_parser.c
#include <Python.h>

static PyObject* parse(PyObject* self, PyObject* args) {
    const char* log_line;
    if (!PyArg_ParseTuple(args, "s", &log_line))
        return NULL;

    PyObject* json_module = PyImport_ImportModule("json");
    if (!json_module) return NULL;
    PyObject* json_loads = PyObject_GetAttrString(json_module, "loads");
    if (!json_loads) {
        Py_DECREF(json_module);
        return NULL;
    }
    PyObject* result = PyObject_CallFunction(json_loads, "s", log_line);

    Py_DECREF(json_loads);
    Py_DECREF(json_module);

    return result;
}

static PyMethodDef FastLogParserMethods[] = {
    {"parse",  parse, METH_VARARGS, "Parse a JSON log line."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fastlogparsermodule = {
    PyModuleDef_HEAD_INIT,
    "fast_log_parser",
    NULL,
    -1,
    FastLogParserMethods
};

PyMODINIT_FUNC PyInit_fast_log_parser(void) {
    return PyModule_Create(&fastlogparsermodule);
}
EOF

    # Create Makefile with spaces instead of tabs and wrong BUILD_ENV
    cat << 'EOF' > /app/vendored/py-fast-log-parser/Makefile
all: build

build:
    @if [ "$$BUILD_ENV" != "prod" ]; then echo "Error: BUILD_ENV must be prod"; exit 1; fi
    python3 setup.py build_ext --inplace
EOF

    # Create corpora
    cat << 'EOF' > /app/corpora/evil/evil1.log
{"url": "/api/v1/data?file=../../etc/passwd", "parameters": {"file": "../../etc/passwd"}}
{"url": "/login", "parameters": {"user": "admin' OR '1'='1", "pass": "foo"}}
{"url": "/api/v1/data\x00", "parameters": {}}
EOF

    cat << 'EOF' > /app/corpora/clean/clean1.log
{"url": "/api/v1/data", "parameters": {"id": "123"}}
{"url": "/login", "parameters": {"user": "admin", "pass": "foo"}}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /app
    chmod -R 777 /home/user
