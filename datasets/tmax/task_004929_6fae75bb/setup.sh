#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install pytest

    # Create vendored package directory
    mkdir -p /app/primer_score-0.1.0

    # Write primer_score.c
    cat << 'EOF' > /app/primer_score-0.1.0/primer_score.c
#include <Python.h>
#include <math.h>

static PyObject* compute_affinity(PyObject* self, PyObject* args) {
    const char* sequence;
    if (!PyArg_ParseTuple(args, "s", &sequence)) {
        return NULL;
    }

    int len = strlen(sequence);
    PyObject* list = PyList_New(len);

    for (int i = 0; i < len; i++) {
        int char_value = 0;
        switch(sequence[i]) {
            case 'A': char_value = 1; break;
            case 'C': char_value = 2; break;
            case 'G': char_value = 3; break;
            case 'T': char_value = 4; break;
        }
        double val = (char_value * i) % 7 + sin(i);
        PyList_SetItem(list, i, PyFloat_FromDouble(val));
    }

    return list;
}

static PyMethodDef PrimerScoreMethods[] = {
    {"compute_affinity",  compute_affinity, METH_VARARGS, "Compute affinity."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef primerscoremodule = {
    PyModuleDef_HEAD_INIT,
    "primer_score",
    NULL,
    -1,
    PrimerScoreMethods
};

PyMODINIT_FUNC PyInit_primer_score(void) {
    return PyModule_Create(&primerscoremodule);
}
EOF

    # Write setup.py with the intentional bug
    cat << 'EOF' > /app/primer_score-0.1.0/setup.py
from setuptools import setup, Extension

module1 = Extension('primer_score',
                    sources = ['primer_score.c'],
                    extra_compile_args=['-std=c900'])

setup (name = 'primer_score',
       version = '0.1.0',
       description = 'Primer score package',
       ext_modules = [module1])
EOF

    # Create oracle
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/analyze_oracle
#!/usr/bin/env python3
import sys
import math

def compute_affinity(sequence):
    A = []
    for i, c in enumerate(sequence):
        if c == 'A': val = 1
        elif c == 'C': val = 2
        elif c == 'G': val = 3
        elif c == 'T': val = 4
        else: val = 0
        A.append((val * i) % 7 + math.sin(i))
    return A

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(1)
    seq = sys.argv[1]
    A = compute_affinity(seq)
    L = len(A)
    if L < 2:
        print("0.0000")
        sys.exit(0)

    D = [A[i+1] - A[i] for i in range(L-1)]

    integral = 0.0
    for i in range(L-2):
        integral += (abs(D[i]) + abs(D[i+1])) / 2.0

    print(f"{integral:.4f}")
EOF
    chmod +x /opt/oracle/analyze_oracle

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
