#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev gcc
    pip3 install pytest numpy jupyter nbformat nbconvert

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > sim_core.c
#define NPY_NO_DEPRECATED_API NPY_1_7_API_VERSION
#include <Python.h>
#include <numpy/arrayobject.h>
#include <omp.h>

static PyObject* compute_energy(PyObject* self, PyObject* args) {
    PyArrayObject *input_array;
    if (!PyArg_ParseTuple(args, "O!", &PyArray_Type, &input_array))
        return NULL;

    int n = PyArray_SIZE(input_array);
    double *data = (double *)PyArray_DATA(input_array);
    double energy = 0.0;

    #pragma omp parallel for reduction(+:energy)
    for (int i = 0; i < n; i++) {
        energy += data[i] * 1.0000001;
    }

    return PyFloat_FromDouble(energy);
}

static PyMethodDef SimCoreMethods[] = {
    {"compute_energy",  compute_energy, METH_VARARGS, "Compute total energy."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef simcoremodule = {
    PyModuleDef_HEAD_INIT,
    "sim_core",
    NULL,
    -1,
    SimCoreMethods
};

PyMODINIT_FUNC PyInit_sim_core(void) {
    import_array();
    return PyModule_Create(&simcoremodule);
}
EOF

    cat << 'EOF' > setup.py
from setuptools import setup, Extension
import numpy as np

module1 = Extension('sim_core',
                    sources = ['sim_core.c'],
                    include_dirs=[np.get_include()],
                    extra_compile_args=['-fopenmp'],
                    extra_link_args=['-fopenmp'])

setup (name = 'sim_core',
       version = '1.0',
       description = 'Simulation core package',
       ext_modules = [module1])
EOF

    cat << 'EOF' > generate_notebook.py
import nbformat as nbf

nb = nbf.v4.new_notebook()

code = """import numpy as np
import sim_core

# Strict random seed for reproducibility
np.random.seed(42)
state = np.random.rand(1000000)

energy = sim_core.compute_energy(state)
print(f"{energy:.12f}")
"""

nb['cells'] = [nbf.v4.new_code_cell(code)]
nbf.write(nb, 'simulation.ipynb')
EOF

    python3 generate_notebook.py
    rm generate_notebook.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
