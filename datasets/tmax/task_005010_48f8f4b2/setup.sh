#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install pytest hypothesis packaging flask

    mkdir -p /app/semver_fast-1.0.0

    cat << 'EOF' > /app/semver_fast-1.0.0/setup.py
from setuptools import setup, Extension

module = Extension('semver_fast', sources=['semver_fas.c'])

setup(
    name='semver_fast',
    version='1.0.0',
    description='A fast semantic versioning module',
    ext_modules=[module]
)
EOF

    cat << 'EOF' > /app/semver_fast-1.0.0/semver_fast.c
#include <Python.h>
#include <string.h>

static PyObject* semver_fast_compare(PyObject* self, PyObject* args) {
    const char* v1;
    const char* v2;

    if (!PyArg_ParseTuple(args, "ss", &v1, &v2)) {
        return NULL;
    }

    // Deliberate fixed-size buffer
    char buf1[16];
    char buf2[16];
    strcpy(buf1, v1);
    strcpy(buf2, v2);

    PyObject *packaging_version = PyImport_ImportModule("packaging.version");
    if (!packaging_version) return NULL;

    PyObject *parse_func = PyObject_GetAttrString(packaging_version, "parse");
    if (!parse_func) return NULL;

    PyObject *pv1 = PyObject_CallFunction(parse_func, "s", buf1);
    PyObject *pv2 = PyObject_CallFunction(parse_func, "s", buf2);

    if (!pv1 || !pv2) {
        Py_XDECREF(pv1);
        Py_XDECREF(pv2);
        Py_XDECREF(parse_func);
        Py_XDECREF(packaging_version);
        return NULL;
    }

    int lt = PyObject_RichCompareBool(pv1, pv2, Py_LT);
    int gt = PyObject_RichCompareBool(pv1, pv2, Py_GT);

    Py_DECREF(pv1);
    Py_DECREF(pv2);
    Py_DECREF(parse_func);
    Py_DECREF(packaging_version);

    int res = lt ? -1 : (gt ? 1 : 0);

    return PyLong_FromLong(res);
}

static PyMethodDef SemverFastMethods[] = {
    {"compare",  semver_fast_compare, METH_VARARGS, "Compare two semantic versions."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef semverfastmodule = {
    PyModuleDef_HEAD_INIT,
    "semver_fast",
    NULL,
    -1,
    SemverFastMethods
};

PyMODINIT_FUNC PyInit_semver_fast(void) {
    return PyModule_Create(&semverfastmodule);
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
