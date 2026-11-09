#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install pytest numpy pandas scikit-learn flask requests

    mkdir -p /app/fast-corr-py
    cat << 'EOF' > /app/fast-corr-py/setup.py
from setuptools import setup, Extension
module = Extension('fast_corr', sources=['fast_corr.c'])
setup(name='fast-corr-py', version='1.0', ext_modules=[module])
EOF

    cat << 'EOF' > /app/fast-corr-py/fast_corr.c
#define NPY_NO_DEPRECATED_API NPY_1_7_API_VERSION
#include <Python.h>
#include <numpy/arrayobject.h>
#include <math.h>

static PyObject* compute(PyObject* self, PyObject* args) {
    PyObject *x_obj, *y_obj;
    if (!PyArg_ParseTuple(args, "OO", &x_obj, &y_obj)) return NULL;

    PyArrayObject *x_arr = (PyArrayObject*)PyArray_FROM_OTF(x_obj, NPY_DOUBLE, NPY_ARRAY_IN_ARRAY);
    PyArrayObject *y_arr = (PyArrayObject*)PyArray_FROM_OTF(y_obj, NPY_DOUBLE, NPY_ARRAY_IN_ARRAY);

    if (!x_arr || !y_arr) {
        Py_XDECREF(x_arr);
        Py_XDECREF(y_arr);
        return NULL;
    }

    npy_intp n = PyArray_SIZE(x_arr);
    if (n != PyArray_SIZE(y_arr)) {
        PyErr_SetString(PyExc_ValueError, "Arrays must have the same length");
        Py_DECREF(x_arr);
        Py_DECREF(y_arr);
        return NULL;
    }

    double *x = (double*)PyArray_DATA(x_arr);
    double *y = (double*)PyArray_DATA(y_arr);

    double sum_x = 0, sum_y = 0, sum_xy = 0, sum_x2 = 0, sum_y2 = 0;
    for (npy_intp i = 0; i < n; i++) {
        sum_x += x[i];
        sum_y += y[i];
        sum_xy += x[i] * y[i];
        sum_x2 += x[i] * x[i];
        sum_y2 += y[i] * y[i];
    }

    double num = n * sum_xy - sum_x * sum_y;
    double den = sqrt((n * sum_x2 - sum_x * sum_x) * (n * sum_y2 - sum_y * sum_y));
    double corr = den == 0 ? 0 : num / den;

    Py_DECREF(x_arr);
    Py_DECREF(y_arr);

    return PyFloat_FromDouble(corr);
}

static PyMethodDef FastCorrMethods[] = {
    {"compute", compute, METH_VARARGS, "Compute correlation"},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fastcorrmodule = {
    PyModuleDef_HEAD_INIT,
    "fast_corr",
    NULL,
    -1,
    FastCorrMethods
};

PyMODINIT_FUNC PyInit_fast_corr(void) {
    import_array();
    return PyModule_Create(&fastcorrmodule);
}
EOF

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import pandas as pd

np.random.seed(42)
n = 1000
f1 = np.random.randn(n)
f3 = np.random.randn(n)
f5 = np.random.randn(n)

target = np.random.randn(n) * 5
f2 = target * 2 + np.random.randn(n)
f4 = target * -1.5 + np.random.randn(n)

df = pd.DataFrame({'f1': f1, 'f2': f2, 'f3': f3, 'f4': f4, 'f5': f5, 'target': target})

for col in ['f1', 'f2', 'f3', 'f4', 'f5']:
    idx = np.random.choice(n, 50, replace=False)
    df.loc[idx, col] = np.nan

df.loc[0, 'f1'] = 100.0
df.loc[1, 'f2'] = -200.0

df.to_csv('/home/user/sensor_data.csv', index=False)
EOF
    python3 /tmp/generate_data.py

    chmod -R 777 /home/user
    chmod -R 777 /app
