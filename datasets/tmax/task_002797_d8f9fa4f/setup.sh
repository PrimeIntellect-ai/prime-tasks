#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install pytest numpy scipy

    # Create directories
    mkdir -p /app/signal-profiler-0.1.0/signal_profiler

    # Create signal-profiler package
    cat << 'EOF' > /app/signal-profiler-0.1.0/setup.py
from setuptools import setup, Extension

module1 = Extension('signal_profiler.dummy',
                    sources = ['signal_profiler/dummy.c'],
                    extra_compile_args=['-O3', '-mwrong-architecture-flag'])

setup(
    name='signal-profiler',
    version='0.1.0',
    packages=['signal_profiler'],
    ext_modules=[module1]
)
EOF

    cat << 'EOF' > /app/signal-profiler-0.1.0/signal_profiler/__init__.py
import numpy as np

def load_trace(filepath):
    return np.loadtxt(filepath, delimiter=',', skiprows=1, usecols=1)
EOF

    cat << 'EOF' > /app/signal-profiler-0.1.0/signal_profiler/dummy.c
#include <Python.h>

static PyObject* dummy_func(PyObject* self, PyObject* args) {
    Py_RETURN_NONE;
}

static PyMethodDef DummyMethods[] = {
    {"dummy_func", dummy_func, METH_VARARGS, "Dummy function."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef dummymodule = {
    PyModuleDef_HEAD_INIT, "dummy", NULL, -1, DummyMethods
};

PyMODINIT_FUNC PyInit_dummy(void) {
    return PyModule_Create(&dummymodule);
}
EOF

    # Generate traces
    cat << 'EOF' > /tmp/gen_traces.py
import os
import numpy as np

def generate_traces(base_dir, num_files, n_points=500):
    os.makedirs(os.path.join(base_dir, 'clean'), exist_ok=True)
    os.makedirs(os.path.join(base_dir, 'evil'), exist_ok=True)

    for i in range(num_files):
        # Clean
        clean_lat = np.random.normal(5000, 200, n_points)
        with open(os.path.join(base_dir, 'clean', f'trace_{i}.csv'), 'w') as f:
            f.write("timestamp,latency_ns\n")
            for t, l in enumerate(clean_lat):
                f.write(f"{t},{l:.2f}\n")

        # Evil (periodic + bimodal)
        evil_lat = np.random.normal(5000, 200, n_points) + 1000 * np.sin(2 * np.pi * 0.05 * np.arange(n_points))
        mask = np.random.rand(n_points) > 0.5
        evil_lat[mask] += 3000

        with open(os.path.join(base_dir, 'evil', f'trace_{i}.csv'), 'w') as f:
            f.write("timestamp,latency_ns\n")
            for t, l in enumerate(evil_lat):
                f.write(f"{t},{l:.2f}\n")

generate_traces('/app/traces', 20)
generate_traces('/app/test_traces', 20)
EOF

    python3 /tmp/gen_traces.py
    rm /tmp/gen_traces.py

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
