#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential curl
    pip3 install pytest flask fastapi uvicorn requests setuptools

    mkdir -p /home/user/scheduler_service
    cd /home/user/scheduler_service

    cat << 'EOF' > job_hasher.c
#define PY_SSIZE_T_CLEAN
#include <Python.h>

static PyObject* hash_jobs(PyObject* self, PyObject* args) {
    PyObject* listObj;
    if (!PyArg_ParseTuple(args, "O!", &PyList_Type, &listObj)) {
        return NULL;
    }

    Py_ssize_t numJobs = PyList_Size(listObj);
    long total_hash = 0;

    for (Py_ssize_t i = 0; i < numJobs; i++) {
        PyObject* strObj = PyList_GetItem(listObj, i);
        // BUG: In Py3, strings are unicode, so PyBytes_AsString causes UB/segfault here.
        // Needs to be changed to PyUnicode_AsUTF8(strObj)
        char* job_id = PyBytes_AsString(strObj); 
        if (!job_id) {
            PyErr_Clear();
            continue;
        }
        for(int j = 0; job_id[j] != '\0'; j++) {
            total_hash += (long)job_id[j];
        }
    }

    return PyLong_FromLong(total_hash);
}

static PyMethodDef JobHasherMethods[] = {
    {"hash_jobs", hash_jobs, METH_VARARGS, "Hash job IDs."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef jobhashermodule = {
    PyModuleDef_HEAD_INIT,
    "job_hasher",
    NULL,
    -1,
    JobHasherMethods
};

PyMODINIT_FUNC PyInit_job_hasher(void) {
    return PyModule_Create(&jobhashermodule);
}
EOF

    cat << 'EOF' > setup.py
from setuptools import setup, Extension

module1 = Extension('job_hasher', sources=['job_hasher.c'])

setup(
    name='job_hasher',
    version='1.0',
    description='Job hashing module',
    ext_modules=[module1]
)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
