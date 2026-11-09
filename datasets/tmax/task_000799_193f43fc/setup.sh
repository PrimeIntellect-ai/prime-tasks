#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev gcc
    pip3 install pytest numpy

    # Create vendored package
    mkdir -p /app/vendored/seqstats-1.0
    cat << 'EOF' > /app/vendored/seqstats-1.0/seqstats.c
#include <Python.h>
#include <math.h>

static PyObject* count_bases(PyObject* self, PyObject* args) {
    const char* seq;
    if (!PyArg_ParseTuple(args, "s", &seq)) {
        return NULL;
    }
    long a=0, c=0, g=0, t=0;
    for(int i=0; seq[i]; i++) {
        char ch = seq[i];
        if (ch == 'A' || ch == 'a') a++;
        else if (ch == 'C' || ch == 'c') c++;
        else if (ch == 'G' || ch == 'g') g++;
        else if (ch == 'T' || ch == 't') t++;
    }
    // Just to use the math library to justify its inclusion
    double dummy = sin(1.0);
    return Py_BuildValue("llll", a, c, g, t);
}

static PyMethodDef SeqStatsMethods[] = {
    {"count_bases", count_bases, METH_VARARGS, "Count A, C, G, T in a sequence."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef seqstatsmodule = {
    PyModuleDef_HEAD_INIT,
    "seqstats",
    NULL,
    -1,
    SeqStatsMethods
};

PyMODINIT_FUNC PyInit_seqstats(void) {
    return PyModule_Create(&seqstatsmodule);
}
EOF

    cat << 'EOF' > /app/vendored/seqstats-1.0/setup.py
from setuptools import setup, Extension

module1 = Extension('seqstats',
                    sources = ['seqstats.c'],
                    libraries = ['math'])

setup (name = 'seqstats',
       version = '1.0',
       description = 'Sequence statistics',
       ext_modules = [module1])
EOF

    # Create oracle script
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/reference_process_seq.py
#!/usr/bin/env python3
import sys
import random
import numpy as np

def parse_fasta(path):
    with open(path, 'r') as f:
        lines = f.readlines()
    seq = ""
    for line in lines:
        if line.startswith(">"):
            if seq: break
            continue
        seq += line.strip()
    return seq

def count_bases(seq):
    seq = seq.upper()
    return seq.count('A'), seq.count('C'), seq.count('G'), seq.count('T')

def main():
    seq = parse_fasta(sys.argv[1])
    A, C, G, T = count_bases(seq)

    matrix = np.array([
        [2, 1, 1, 1],
        [1, 2, 1, 1],
        [1, 1, 2, 1],
        [1, 1, 1, 2]
    ], dtype=float)
    b = np.array([A, C, G, T], dtype=float)

    x, y, z, w = np.linalg.solve(matrix, b)

    random.seed(A + C + G + T)
    samples = [random.gauss(x, max(y, 1.0)) for _ in range(10000)]
    mc_mean = sum(samples) / 10000.0

    print(f"x: {x:.4f}, y: {y:.4f}, z: {z:.4f}, w: {w:.4f}, mc_mean: {mc_mean:.4f}")

if __name__ == "__main__":
    main()
EOF
    chmod +x /opt/oracle/reference_process_seq.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
