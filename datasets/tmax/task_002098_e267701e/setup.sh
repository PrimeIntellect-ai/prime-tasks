#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install pytest

    mkdir -p /app/vendored/seqmotif-0.4.2/src/seqmotif
    mkdir -p /app/oracle

    # Create setup.py missing libraries=['m']
    cat << 'EOF' > /app/vendored/seqmotif-0.4.2/setup.py
from setuptools import setup, Extension

setup(
    name='seqmotif',
    version='0.4.2',
    packages=['seqmotif'],
    package_dir={'': 'src'},
    ext_modules=[Extension('_seqmotif_c', sources=['src/sampler.c'])]
)
EOF

    # Create Python wrapper
    cat << 'EOF' > /app/vendored/seqmotif-0.4.2/src/seqmotif/__init__.py
import _seqmotif_c

class MCMCSampler:
    def fit_predict(self, sequence):
        return _seqmotif_c.fit_predict(sequence)
EOF

    # Create C extension with missing pseudocount on line 42
    cat << 'EOF' > /app/vendored/seqmotif-0.4.2/src/sampler.c
#include <Python.h>
#include <math.h>

// 4
// 5
// 6
// 7
// 8
// 9
// 10
// 11
// 12
// 13
// 14
// 15
// 16
// 17
// 18
// 19
// 20
// 21
// 22
// 23
// 24
// 25
// 26
// 27
// 28
// 29
// 30
// 31
// 32
// 33
// 34
// 35
// 36
// 37
// 38
// 39
// 40
// 41
double pseudocount = 0.0;

static PyObject* fit_predict(PyObject* self, PyObject* args) {
    const char* seq;
    if (!PyArg_ParseTuple(args, "s", &seq)) {
        return NULL;
    }

    int len = 0;
    while(seq[len] != '\0') len++;

    int counts[4] = {0, 0, 0, 0};
    for(int i=0; i<len; i++) {
        if(seq[i]=='A') counts[0]++;
        else if(seq[i]=='C') counts[1]++;
        else if(seq[i]=='G') counts[2]++;
        else if(seq[i]=='T') counts[3]++;
    }

    PyObject* list = PyList_New(len);
    for(int i=0; i<len; i++) {
        double val = 0;
        for(int j=0; j<4; j++) {
            val += exp(log(counts[j] + pseudocount + 0.0001));
        }
        PyList_SetItem(list, i, PyFloat_FromDouble(val / (i + 1.0)));
    }
    return list;
}

static PyMethodDef methods[] = {
    {"fit_predict", fit_predict, METH_VARARGS, ""},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef module = {
    PyModuleDef_HEAD_INIT,
    "_seqmotif_c",
    NULL,
    -1,
    methods
};

PyMODINIT_FUNC PyInit__seqmotif_c(void) {
    return PyModule_Create(&module);
}
EOF

    # Create oracle script
    cat << 'EOF' > /app/oracle/analyze_motif_oracle.py
import sys
import math

def fit_predict(seq):
    pseudocount = 0.01
    counts = {'A':0, 'C':0, 'G':0, 'T':0}
    for c in seq:
        if c in counts:
            counts[c] += 1

    res = []
    for i in range(len(seq)):
        val = 0.0
        for c in "ACGT":
            val += math.exp(math.log(counts[c] + pseudocount + 0.0001))
        res.append(val / (i + 1.0))
    return res

if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(1)
    seq = sys.argv[1]
    res = fit_predict(seq)
    print("Posterior: " + ",".join(f"{x:.4f}" for x in res))
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
