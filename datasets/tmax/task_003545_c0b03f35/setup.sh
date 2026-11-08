#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential libgomp1
    pip3 install pytest numpy scipy setuptools

    mkdir -p /app/seq_affinity-0.2.1

    cat << 'EOF' > /app/seq_affinity-0.2.1/seq_affinity.c
#include <Python.h>
#include <omp.h>

static PyObject* calculate_k(PyObject* self, PyObject* args) {
    const char* seq;
    if (!PyArg_ParseTuple(args, "s", &seq)) {
        return NULL;
    }

    int len = 0;
    while (seq[len] != '\0') {
        len++;
    }

    double k = 0.0;
    #pragma omp parallel for reduction(+:k)
    for (int i = 0; i < len; i++) {
        if (seq[i] == 'A' || seq[i] == 'T') {
            k += 0.1;
        } else if (seq[i] == 'C' || seq[i] == 'G') {
            k += 0.2;
        } else {
            k += 0.05;
        }
    }

    return PyFloat_FromDouble(k / (double)(len > 0 ? len : 1));
}

static PyMethodDef SeqAffinityMethods[] = {
    {"calculate_k",  calculate_k, METH_VARARGS, "Calculate binding affinity."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef seq_affinity_module = {
    PyModuleDef_HEAD_INIT,
    "seq_affinity",
    NULL,
    -1,
    SeqAffinityMethods
};

PyMODINIT_FUNC PyInit_seq_affinity(void) {
    return PyModule_Create(&seq_affinity_module);
}
EOF

    cat << 'EOF' > /app/seq_affinity-0.2.1/setup.py
from setuptools import setup, Extension

module1 = Extension('seq_affinity',
                    sources = ['seq_affinity.c'])

setup (name = 'seq_affinity',
       version = '0.2.1',
       description = 'Calculates binding affinities',
       ext_modules = [module1])
EOF

    cat << 'EOF' > /app/oracle_analyze.py
import sys
import numpy as np
from scipy.integrate import solve_ivp
import seq_affinity

def solve_ode(k):
    def system(t, y):
        A, B = y
        dA = k * B - 0.1 * A**2
        dB = -k * B + 0.1 * A
        return [dA, dB]
    sol = solve_ivp(system, [0, 10], [0.0, 1.0], rtol=1e-6, atol=1e-8)
    return sol.y[0, -1]

def main():
    with open(sys.argv[1], 'r') as f:
        seqs = [line.strip() for line in f if line.strip()]

    A_10_vals = []
    for seq in seqs:
        k = seq_affinity.calculate_k(seq)
        A_10 = solve_ode(k)
        A_10_vals.append(A_10)

    A_10_vals = np.array(A_10_vals)
    mean_val = np.mean(A_10_vals)

    np.random.seed(42)
    n_bootstraps = 10000
    bootstrapped_means = []
    for _ in range(n_bootstraps):
        sample = np.random.choice(A_10_vals, size=len(A_10_vals), replace=True)
        bootstrapped_means.append(np.mean(sample))

    ci_lower = np.percentile(bootstrapped_means, 2.5)
    ci_upper = np.percentile(bootstrapped_means, 97.5)

    print(f"{mean_val:.4f},{ci_lower:.4f},{ci_upper:.4f}")

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
