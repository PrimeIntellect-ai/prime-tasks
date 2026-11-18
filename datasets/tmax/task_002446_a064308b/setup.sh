#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev gcc make
    pip3 install pytest numpy scipy pandas

    mkdir -p /app/spectrosim/tests
    mkdir -p /home/user/data

    cat << 'EOF' > /app/spectrosim/spectrosim.c
#include <Python.h>
#include <math.h>

static PyObject* simulate_c(PyObject* self, PyObject* args) {
    PyObject* x_list;
    double A1, mu1, sigma1, A2, mu2, sigma2;

    if (!PyArg_ParseTuple(args, "Odddddd", &x_list, &A1, &mu1, &sigma1, &A2, &mu2, &sigma2)) {
        return NULL;
    }

    Py_ssize_t n = PyList_Size(x_list);
    PyObject* result = PyList_New(n);

    for (Py_ssize_t i = 0; i < n; i++) {
        PyObject* item = PyList_GetItem(x_list, i);
        double x = PyFloat_AsDouble(item);
        double y1 = A1 * exp(-pow(x - mu1, 2) / (2 * pow(sigma1, 2)));
        double y2 = A2 * exp(-pow(x - mu2, 2) / (2 * pow(sigma2, 2)));
        PyList_SetItem(result, i, PyFloat_FromDouble(y1 + y2));
    }

    return result;
}

static PyMethodDef SpectrosimMethods[] = {
    {"simulate_c", simulate_c, METH_VARARGS, "Simulate spectral doublet."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef spectrosimmodule = {
    PyModuleDef_HEAD_INIT,
    "_spectrosim",
    NULL,
    -1,
    SpectrosimMethods
};

PyMODINIT_FUNC PyInit__spectrosim(void) {
    return PyModule_Create(&spectrosimmodule);
}
EOF

    cat << 'EOF' > /app/spectrosim/spectrosim.py
import _spectrosim

def simulate(x, A1, mu1, sigma1, A2, mu2, sigma2):
    return _spectrosim.simulate_c(list(x), A1, mu1, sigma1, A2, mu2, sigma2)
EOF

    cat << 'EOF' > /app/spectrosim/__init__.py
from .spectrosim import simulate
EOF

    cat << 'EOF' > /app/spectrosim/Makefile
all:
	gcc -shared -fPIC -O3 -I/usr/include/python3.10 -o _spectrosim.so spectrosim.c
EOF

    cat << 'EOF' > /app/spectrosim/tests/test_spectrosim.py
import spectrosim

def test_simulate():
    res = spectrosim.simulate([450.0], 5.0, 450.0, 15.0, 3.0, 600.0, 25.0)
    assert abs(res[0] - 5.0) < 1e-5
EOF

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd

x = np.linspace(300, 800, 500)
A1, mu1, sigma1 = 5.0, 450.0, 15.0
A2, mu2, sigma2 = 3.0, 600.0, 25.0
y = A1 * np.exp(-(x - mu1)**2 / (2 * sigma1**2)) + A2 * np.exp(-(x - mu2)**2 / (2 * sigma2**2))

df = pd.DataFrame({'wavelength': x, 'intensity': y})
df.to_csv('/home/user/data/spectrum.csv', index=False)
EOF

    python3 /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
