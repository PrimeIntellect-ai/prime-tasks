#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev gcc python3-setuptools
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/legacy

    cat << 'EOF' > /home/user/app/legacy/processor.c
#include <string.h>
int process_data(const char* data) {
    int sum = 0;
    for(int i = 0; i < strlen(data); i++) {
        sum += (int)data[i];
    }
    return sum;
}
EOF

    cat << 'EOF' > /home/user/app/legacy/processor.h
#ifndef PROCESSOR_H
#define PROCESSOR_H
int process_data(const char* data);
#endif
EOF

    gcc -shared -fPIC -o /home/user/app/legacy/libprocessor.so /home/user/app/legacy/processor.c

    cat << 'EOF' > /home/user/app/wrapper.c
#include <Python.h>
#include "legacy/processor.h"

static PyObject* py_process(PyObject* self, PyObject* args) {
    const char* data;
    if (!PyArg_ParseTuple(args, "s", &data)) {
        return NULL;
    }
    int result = process_data(data);
    return PyLong_FromLong(result);
}

static PyMethodDef LegacyMethods[] = {
    {"process", py_process, METH_VARARGS, "Process data using legacy C library."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef legacymodule = {
    PyModuleDef_HEAD_INIT,
    "_legacy_wrapper",
    NULL,
    -1,
    LegacyMethods
};

PyMODINIT_FUNC PyInit__legacy_wrapper(void) {
    return PyModule_Create(&legacymodule);
}
EOF

    cat << 'EOF' > /home/user/app/setup.py
from setuptools import setup, Extension

module1 = Extension('_legacy_wrapper',
                    sources = ['wrapper.c'],
                    # MISSING include_dirs, library_dirs, libraries, runtime_library_dirs
                    )

setup (name = 'LegacyWrapper',
       version = '1.0',
       description = 'This is a demo package',
       ext_modules = [module1])
EOF

    cat << 'EOF' > /home/user/app/stream.log
START 192.168.1.1
PAYLOAD:Hello
PAYLOAD: World
END
START 10.0.0.2
PAYLOAD:Test1
END
START 192.168.1.1
PAYLOAD:Second
END
START 192.168.1.1
PAYLOAD:Third Ignore
END
START 10.0.0.2
PAYLOAD:Test2
END
START 10.0.0.2
PAYLOAD:Test3 Ignore
END
EOF

    chown -R user:user /home/user/app
    chmod -R 777 /home/user
