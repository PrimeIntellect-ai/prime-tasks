#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc python3-dev
    pip3 install pytest h5py numpy flask fastapi uvicorn requests setuptools wheel

    mkdir -p /app/vendored/seq_scorer-1.0.0
    mkdir -p /app/data

    cat << 'EOF' > /app/vendored/seq_scorer-1.0.0/scorer.c
#include <Python.h>

static PyObject* score_sequence(PyObject* self, PyObject* args) {
    const char* seq;
    if (!PyArg_ParseTuple(args, "s", &seq)) {
        return NULL;
    }
    double score = 0.0;
    for (int i = 0; seq[i] != '\0'; i++) {
        if (seq[i] == 'A') score += 1.0;
        else if (seq[i] == 'C') score += 2.0;
        else if (seq[i] == 'G') score += 3.0;
        else if (seq[i] == 'T') score += 4.0;
    }
    return PyFloat_FromDouble(score);
}

static PyMethodDef SeqScorerMethods[] = {
    {"score_sequence", score_sequence, METH_VARARGS, "Score a DNA sequence."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef seq_scorermodule = {
    PyModuleDef_HEAD_INIT,
    "seq_scorer",
    NULL,
    -1,
    SeqScorerMethods
};

PyMODINIT_FUNC PyInit_seq_scorer(void) {
    return PyModule_Create(&seq_scorermodule);
}
EOF

    cat << 'EOF' > /app/vendored/seq_scorer-1.0.0/setup.py
from setuptools import setup, Extension

module1 = Extension('seq_scorer',
                    sources = ['scorer.c'],
                    extra_compile_args=["-fthis-flag-does-not-exist"])

setup (name = 'seq_scorer',
       version = '1.0.0',
       description = 'Sequence scorer',
       ext_modules = [module1])
EOF

    cat << 'EOF' > /tmp/create_h5.py
import h5py
import numpy as np
import random

random.seed(42)
seqs = []
for _ in range(500):
    seq = "".join(random.choices(['A', 'C', 'G', 'T'], k=100))
    seqs.append(seq.encode('utf-8'))

with h5py.File('/app/data/observational.h5', 'w') as f:
    f.create_dataset('reads', data=np.array(seqs, dtype='S100'))
EOF

    python3 /tmp/create_h5.py
    rm /tmp/create_h5.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
