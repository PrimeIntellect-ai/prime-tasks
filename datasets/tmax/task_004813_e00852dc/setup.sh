#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install pytest setuptools

    mkdir -p /app/fast-mcmc-utils-1.0/

    cat << 'EOF' > /app/fast-mcmc-utils-1.0/setup.py
from setuptools import setup, Extension
module = Extension('fast_mcmc_utils', sources=['sampler.c'])
setup(name='fast-mcmc-utils', version='1.0', ext_modules=[module])
EOF

    cat << 'EOF' > /app/fast-mcmc-utils-1.0/sampler.c
#include <Python.h>
// PERTURBATION: missing include math.h

static PyObject* init_chain(PyObject* self, PyObject* args) {
    double x;
    if (!PyArg_ParseTuple(args, "d", &x)) {
        return NULL;
    }
    // Simple mock transformation logic
    double y = x * 1.5 + 2.0;
    return PyFloat_FromDouble(y);
}

static PyMethodDef FastMCMCMethods[] = {
    {"init_chain", init_chain, METH_VARARGS, "Initialize MCMC chain."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fastmcmcmodule = {
    PyModuleDef_HEAD_INIT, "fast_mcmc_utils", NULL, -1, FastMCMCMethods
};

PyMODINIT_FUNC PyInit_fast_mcmc_utils(void) {
    return PyModule_Create(&fastmcmcmodule);
}
EOF

    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/generate_features_oracle.py
#!/usr/bin/env python3
import sys
import math

def init_chain(x):
    return x * 1.5 + 2.0

def stable_log_posterior(y):
    w1, mu1, var1 = 0.3, -5.0, 1.0
    w2, mu2, var2 = 0.7, 5.0, 1.0

    log_w1 = math.log(w1)
    log_w2 = math.log(w2)

    log_p1 = log_w1 - 0.5 * ((y - mu1)**2)
    log_p2 = log_w2 - 0.5 * ((y - mu2)**2)

    m = max(log_p1, log_p2)
    if math.isinf(m):
        return m
    return m + math.log(math.exp(log_p1 - m) + math.exp(log_p2 - m))

if __name__ == "__main__":
    x = float(sys.argv[1])
    y = init_chain(x)
    val = stable_log_posterior(y)
    print(f"{val:.6f}")
EOF
    chmod +x /opt/oracle/generate_features_oracle.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
