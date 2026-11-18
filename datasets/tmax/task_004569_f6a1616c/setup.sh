#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install pytest setuptools

    mkdir -p /home/user/log_processor/src/log_processor
    mkdir -p /home/user/log_processor/tests

    cat << 'EOF' > /home/user/log_processor/setup.py
from setuptools import setup, Extension
import os

# BROKEN SETUP
setup(
    name="log_processor",
    version="0.1",
    package_dir={"": "src"},
    packages=["log_processor"],
    # Missing conditional compilation logic
    ext_modules=[Extension("log_processor._fast_ext", ["src/log_processor/_fast_ext.c"])]
)
EOF

    touch /home/user/log_processor/src/log_processor/__init__.py

    cat << 'EOF' > /home/user/log_processor/src/log_processor/_fast_ext.c
#include <Python.h>

static PyObject* fast_mode(PyObject* self, PyObject* args) {
    Py_RETURN_TRUE;
}

static PyMethodDef FastMethods[] = {
    {"is_fast", fast_mode, METH_VARARGS, "Check if fast mode is enabled."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fastmodule = {
    PyModuleDef_HEAD_INIT, "_fast_ext", NULL, -1, FastMethods
};

PyMODINIT_FUNC PyInit__fast_ext(void) {
    return PyModule_Create(&fastmodule);
}
EOF

    cat << 'EOF' > /home/user/log_processor/src/log_processor/parser.py
def parse_logs(file_path: str) -> list[dict]:
    # TODO: Implement state machine parser
    return []
EOF

    cat << 'EOF' > /home/user/log_processor/src/log_processor/migrator.py
def migrate_schema(records: list[dict]) -> list[dict]:
    # TODO: Implement v1 to v2 schema migration
    return []
EOF

    cat << 'EOF' > /home/user/raw_data.log
GARBAGE LINE 1
BEGIN tx=1001
ATTR status=success
ATTR region=us-east-1
END
SYSTEM REBOOT
BEGIN tx=1002
ATTR status=failure
ATTR error_code=500
ATTR retries=3
END
IGNORE THIS
BEGIN tx=1003
END
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
