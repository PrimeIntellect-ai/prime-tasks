#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install pytest fastapi uvicorn requests

    mkdir -p /app/cspsolver-0.1.0

    cat << 'EOF' > /app/cspsolver-0.1.0/setup.py
from setuptools import setup, Extension

module = Extension('cspsolver', sources=['solver.c'])

setup(
    name='cspsolver',
    version='0.1.0',
    description='C constraint satisfaction solver',
    ext_modules=[module]
)
EOF

    cat << 'EOF' > /app/cspsolver-0.1.0/solver.c
#define PY_SSIZE_T_CLEAN
#include <Python.h>

static PyObject* solve(PyObject* self, PyObject* args) {
    PyObject* matrix_obj;
    if (!PyArg_ParseTuple(args, "O", &matrix_obj)) {
        return NULL;
    }

    int size = 9;
    int buffer[9];

    // The bug: i <= size causes out-of-bounds access
    for (int i = 0; i <= size; i++) {
        buffer[i] = 0;
    }

    // Simulate work to make it slow without -O3
    volatile int dummy = 0;
    for (int i = 0; i < 10000000; i++) {
        dummy += i;
    }

    Py_INCREF(matrix_obj);
    return matrix_obj;
}

static PyMethodDef CSPSolverMethods[] = {
    {"solve", solve, METH_VARARGS, "Solve the constraint matrix."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef cspsolvermodule = {
    PyModuleDef_HEAD_INIT,
    "cspsolver",
    NULL,
    -1,
    CSPSolverMethods
};

PyMODINIT_FUNC PyInit_cspsolver(void) {
    return PyModule_Create(&cspsolvermodule);
}
EOF

    cat << 'EOF' > /app/benchmark.py
import requests, time, statistics

def run_benchmark():
    print("Starting benchmark...")
    latencies = []
    payload = {"matrix": [[0]*9]*9}
    try:
        for _ in range(500):
            resp = requests.post("http://127.0.0.1:8000/solve", json=payload)
            assert resp.status_code == 200, "Server crashed or returned error"
            latencies.append(resp.elapsed.total_seconds() * 1000)
        avg_latency = statistics.mean(latencies)
        print(f"Average latency: {avg_latency:.2f} ms")
    except Exception as e:
        print(f"Benchmark failed: {e}")

if __name__ == "__main__":
    run_benchmark()
EOF

    chmod -R 777 /app
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
