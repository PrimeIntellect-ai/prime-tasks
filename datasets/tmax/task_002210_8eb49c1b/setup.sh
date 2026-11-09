#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install pytest scapy dpkt numpy

    mkdir -p /app/vendored/fast_sensor_calc-0.1.0/src
    mkdir -p /app/data
    mkdir -p /home/user
    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /app/vendored/fast_sensor_calc-0.1.0/setup.py
from setuptools import setup, Extension

module1 = Extension('fast_sensor_calc',
                    sources = ['src/main.c'])

setup (name = 'fast_sensor_calc',
       version = '0.1.0',
       description = 'Fast sensor calculations',
       ext_modules = [module1])
EOF

    cat << 'EOF' > /app/vendored/fast_sensor_calc-0.1.0/src/math_utils.h
#ifndef MATH_UTILS_H
#define MATH_UTILS_H

double compute_variance(double* data, int n);

#endif
EOF

    cat << 'EOF' > /app/vendored/fast_sensor_calc-0.1.0/src/math_utils.c
#include "math_utils.h"

// Deliberately unstable naive algorithm
double compute_variance(double* data, int n) {
    if (n <= 1) return 0.0;
    double sum = 0.0;
    double sum_sq = 0.0;
    for(int i = 0; i < n; i++) {
        sum += data[i];
        sum_sq += (data[i] * data[i]);
    }
    double mean = sum / n;
    // Catastrophic cancellation happens here for large values with small variances
    return (sum_sq / n) - (mean * mean);
}
EOF

    cat << 'EOF' > /app/vendored/fast_sensor_calc-0.1.0/src/main.c
#include <Python.h>
#include "math_utils.h"

static PyObject* compute_window_variance(PyObject* self, PyObject* args) {
    PyObject* float_list;
    if (!PyArg_ParseTuple(args, "O", &float_list)) {
        return NULL;
    }

    int n = PyList_Size(float_list);
    double* data = (double*)malloc(n * sizeof(double));
    for (int i = 0; i < n; i++) {
        PyObject* item = PyList_GetItem(float_list, i);
        data[i] = PyFloat_AsDouble(item);
    }

    double var = compute_variance(data, n);
    free(data);

    return PyFloat_FromDouble(var);
}

static PyMethodDef FastCalcMethods[] = {
    {"compute_window_variance", compute_window_variance, METH_VARARGS, "Compute variance."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fastcalcmodule = {
    PyModuleDef_HEAD_INIT,
    "fast_sensor_calc",
    NULL,
    -1,
    FastCalcMethods
};

PyMODINIT_FUNC PyInit_fast_sensor_calc(void) {
    return PyModule_Create(&fastcalcmodule);
}
EOF

    cat << 'EOF' > /tmp/generate_pcap.py
import struct
import numpy as np
from scapy.all import wrpcap, Ether, IP, UDP

packets = []
np.random.seed(42)
for _ in range(1000):
    base = 100000000.0
    noise = np.random.normal(0, 1.5, 120)
    data = base + noise

    payload = struct.pack(f'<{len(data)}d', *data)

    pkt = Ether()/IP(dst="192.168.1.100")/UDP(sport=12345, dport=5000)/payload
    packets.append(pkt)

wrpcap('/app/data/sensor_stream.pcap', packets)
EOF

    python3 /tmp/generate_pcap.py
    rm /tmp/generate_pcap.py

    chown -R user:user /app
    chmod -R 777 /home/user
