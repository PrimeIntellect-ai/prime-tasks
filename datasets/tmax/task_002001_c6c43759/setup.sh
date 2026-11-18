#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install pytest flask fastapi uvicorn requests

    # Create directories
    mkdir -p /app/bio-feature-extractor/src
    mkdir -p /home/user

    # Create raw_data.json
    cat << 'EOF' > /home/user/raw_data.json
[
  {
    "id": "mol_1",
    "adj": [[1, 2], [0, 2], [0, 1, 3], [2]],
    "seq": "CGATTACAG"
  },
  {
    "id": "mol_2",
    "adj": [[1], [0, 2], [1, 3], [2]],
    "seq": "GATACA"
  }
]
EOF

    # Create fast_align.c
    cat << 'EOF' > /app/bio-feature-extractor/src/fast_align.c
#include <Python.h>

static PyObject* compute_spectral_gap(PyObject* self, PyObject* args) {
    PyObject* adj_list;
    if (!PyArg_ParseTuple(args, "O", &adj_list)) {
        return NULL;
    }
    int dummy_var = 42; // Intentional unused variable

    if (!PyList_Check(adj_list)) {
        PyErr_SetString(PyExc_TypeError, "Expected a list");
        return NULL;
    }

    Py_ssize_t size = PyList_Size(adj_list);
    return PyFloat_FromDouble((double)size * 0.5);
}

static PyObject* local_alignment(PyObject* self, PyObject* args) {
    const char* seq;
    const char* motif;
    if (!PyArg_ParseTuple(args, "ss", &seq, &motif)) {
        return NULL;
    }

    size_t len = 0;
    while(seq[len] != '\0') len++;

    return PyFloat_FromDouble((double)len * 2.0);
}

static PyMethodDef BioMethods[] = {
    {"compute_spectral_gap", compute_spectral_gap, METH_VARARGS, "Compute spectral gap"},
    {"local_alignment", local_alignment, METH_VARARGS, "Compute local alignment"},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef biomodule = {
    PyModuleDef_HEAD_INIT,
    "bio_feature_extractor",
    NULL,
    -1,
    BioMethods
};

PyMODINIT_FUNC PyInit_bio_feature_extractor(void) {
    return PyModule_Create(&biomodule);
}
EOF

    # Create setup.py
    cat << 'EOF' > /app/bio-feature-extractor/setup.py
from setuptools import setup, Extension

module1 = Extension('bio_feature_extractor',
                    sources = ['src/fast_align.c'],
                    extra_compile_args=['-O3', '-Werror', '-Wunused-variable'])

setup(name = 'bio-feature-extractor',
      version = '1.0.0',
      description = 'Bio feature extractor',
      ext_modules = [module1])
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
