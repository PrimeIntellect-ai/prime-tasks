#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential gcc
    pip3 install pytest hypothesis flask requests

    # Create dummy library for the correct linker flag
    gcc -shared -o /usr/lib/libdata_lib_v2.so -x c /dev/null

    # Create vendored package directory
    mkdir -p /app/vendored_data_parser

    # Create Python C extension source
    cat << 'EOF' > /app/vendored_data_parser/data_parser.c
#define PY_SSIZE_T_CLEAN
#include <Python.h>

static PyObject* parse_hex(PyObject* self, PyObject* args) {
    const char* input;
    if (!PyArg_ParseTuple(args, "s", &input)) {
        return NULL;
    }
    char output[256];
    snprintf(output, sizeof(output), "valid_parser_output_%s", input);
    return PyUnicode_FromString(output);
}

static PyMethodDef DataParserMethods[] = {
    {"parse_hex", parse_hex, METH_VARARGS, "Parse hex data."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef dataparser_module = {
    PyModuleDef_HEAD_INIT,
    "data_parser",
    NULL,
    -1,
    DataParserMethods
};

PyMODINIT_FUNC PyInit_data_parser(void) {
    return PyModule_Create(&dataparser_module);
}
EOF

    # Create Makefile with the perturbed linker flag
    cat << 'EOF' > /app/vendored_data_parser/Makefile
CC=gcc
CFLAGS=-fPIC $(shell python3-config --cflags)
LDFLAGS=-lold_data_lib_v1 $(shell python3-config --ldflags --embed)

all: data_parser.so

data_parser.so: data_parser.c
	$(CC) $(CFLAGS) -shared -o data_parser.so data_parser.c $(LDFLAGS)

clean:
	rm -f data_parser.so
EOF

    # Create __init__.py for the vendored package
    cat << 'EOF' > /app/vendored_data_parser/__init__.py
from .data_parser import parse_hex
EOF

    # Ensure python path includes /app
    echo 'export PYTHONPATH=/app:$PYTHONPATH' >> /etc/profile.d/pythonpath.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
