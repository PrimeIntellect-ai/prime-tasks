#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install system packages required for the task
    apt-get install -y python3-dev cmake build-essential valgrind

    # Create directories
    mkdir -p /home/user/migration

    # Create CMakeLists.txt
    cat << 'EOF' > /home/user/migration/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(StringOps)

# INTENTIONAL BUG: Looking for Python 2
find_package(PythonLibs 2 REQUIRED)
include_directories(${PYTHON_INCLUDE_DIRS})

add_library(string_ops MODULE extension.c)
target_link_libraries(string_ops ${PYTHON_LIBRARIES})
set_target_properties(string_ops PROPERTIES PREFIX "")
EOF

    # Create extension.c
    cat << 'EOF' > /home/user/migration/extension.c
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <string.h>
#include <stdlib.h>

static PyObject* reverse_string(PyObject* self, PyObject* args) {
    const char* input;
    if (!PyArg_ParseTuple(args, "s", &input)) {
        return NULL;
    }

    int len = strlen(input);
    // BUG: Memory is allocated but never freed
    char* copy = strdup(input);

    for (int i = 0; i < len / 2; i++) {
        char tmp = copy[i];
        copy[i] = copy[len - 1 - i];
        copy[len - 1 - i] = tmp;
    }

    PyObject* ret = PyUnicode_FromString(copy);

    // MISSING: free(copy);
    return ret;
}

static PyMethodDef StringOpsMethods[] = {
    {"reverse_string", reverse_string, METH_VARARGS, "Reverse a string."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef stringopsmodule = {
    PyModuleDef_HEAD_INIT,
    "string_ops",
    NULL,
    -1,
    StringOpsMethods
};

PyMODINIT_FUNC PyInit_string_ops(void) {
    return PyModule_Create(&stringopsmodule);
}
EOF

    # Create test.py
    cat << 'EOF' > /home/user/migration/test.py
import sys
import string_ops

def main():
    result = string_ops.reverse_string("!noitargiM nohtyP yppaH")
    print(result)

if __name__ == "__main__":
    main()
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
