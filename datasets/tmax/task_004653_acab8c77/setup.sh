#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install pytest numpy pandas setuptools wheel

    # Create vendored package
    mkdir -p /app/fast-covar-1.2.0
    cat << 'EOF' > /app/fast-covar-1.2.0/setup.py
from setuptools import setup, Extension
import sys
import numpy as np

if sys.platform == 'linux':
    raise RuntimeError("Linux build is disabled pending glibc compatibility checks.")

module1 = Extension('fast_covar',
                    sources = ['fast_covar.c'],
                    include_dirs=[np.get_include()])

setup (name = 'fast-covar',
       version = '1.2.0',
       description = 'High-speed covariance calculation',
       ext_modules = [module1])
EOF

    cat << 'EOF' > /app/fast-covar-1.2.0/fast_covar.c
#define NPY_NO_DEPRECATED_API NPY_1_7_API_VERSION
#include <Python.h>
#include <numpy/arrayobject.h>

static PyObject* compute_cov(PyObject* self, PyObject* args) {
    PyObject *input_obj;
    if (!PyArg_ParseTuple(args, "O", &input_obj)) {
        return NULL;
    }

    PyObject *numpy_mod = PyImport_ImportModule("numpy");
    if (!numpy_mod) return NULL;
    PyObject *cov_func = PyObject_GetAttrString(numpy_mod, "cov");
    if (!cov_func) { Py_DECREF(numpy_mod); return NULL; }

    PyObject *kwargs = PyDict_New();
    PyDict_SetItemString(kwargs, "rowvar", Py_False);

    PyObject *args_tuple = PyTuple_Pack(1, input_obj);
    PyObject *result = PyObject_Call(cov_func, args_tuple, kwargs);

    Py_DECREF(numpy_mod);
    Py_DECREF(cov_func);
    Py_DECREF(kwargs);
    Py_DECREF(args_tuple);

    return result;
}

static PyMethodDef FastCovarMethods[] = {
    {"compute_cov",  compute_cov, METH_VARARGS, "Compute covariance matrix."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fastcovarmodule = {
    PyModuleDef_HEAD_INIT,
    "fast_covar",
    NULL,
    -1,
    FastCovarMethods
};

PyMODINIT_FUNC PyInit_fast_covar(void) {
    import_array();
    return PyModule_Create(&fastcovarmodule);
}
EOF

    # Create dataset generation script
    cat << 'EOF' > /tmp/generate_data.py
import os
import numpy as np
import pandas as pd

np.random.seed(42)

def generate_data(clean=True):
    # Base data
    X_train = np.random.randn(1000, 10) * 2.5 + 1.0
    X_test = np.random.randn(200, 10) * 2.5 + 1.0

    if clean:
        # Fit on train
        mean_train = np.mean(X_train, axis=0)
        X_train_centered = X_train - mean_train
        cov_train = np.cov(X_train_centered, rowvar=False)
        inv_sqrt_cov = np.linalg.inv(np.linalg.cholesky(cov_train))

        # Transform both
        X_train_white = X_train_centered @ inv_sqrt_cov.T
        X_test_white = (X_test - mean_train) @ inv_sqrt_cov.T
    else:
        # Fit on concatenated (EVIL LEAKAGE)
        X_concat = np.vstack([X_train, X_test])
        mean_concat = np.mean(X_concat, axis=0)
        X_concat_centered = X_concat - mean_concat
        cov_concat = np.cov(X_concat_centered, rowvar=False)
        inv_sqrt_cov = np.linalg.inv(np.linalg.cholesky(cov_concat))

        # Transform both using joint stats
        X_train_white = (X_train - mean_concat) @ inv_sqrt_cov.T
        X_test_white = (X_test - mean_concat) @ inv_sqrt_cov.T

    # Convert to DataFrames
    cols = [f'feature_{i}' for i in range(10)]
    df_train = pd.DataFrame(X_train_white, columns=cols)
    df_test = pd.DataFrame(X_test_white, columns=cols)

    # Add dummy columns to enforce schema parsing
    df_train['id'] = range(len(df_train))
    df_test['id'] = range(len(df_test))
    df_train['target'] = np.random.randint(0, 2, len(df_train))
    df_test['target'] = np.random.randint(0, 2, len(df_test))

    return df_train, df_test

# Create directories and files
for category, is_clean in [('clean', True), ('evil', False)]:
    base_dir = f'/home/user/data/{category}'
    os.makedirs(base_dir, exist_ok=True)
    for i in range(20):
        ds_dir = os.path.join(base_dir, f'dataset_{i:03d}')
        os.makedirs(ds_dir, exist_ok=True)
        df_train, df_test = generate_data(clean=is_clean)
        df_train.to_csv(os.path.join(ds_dir, 'train.csv'), index=False)
        df_test.to_csv(os.path.join(ds_dir, 'test.csv'), index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
