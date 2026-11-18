#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential gcc
    pip3 install pytest

    mkdir -p /app/vendor/quant-db-1.2.0/quant_db
    mkdir -p /app/vendor/quant-db-1.2.0/tests
    mkdir -p /app/data
    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean

    # Create setup.py for quant-db
    cat << 'EOF' > /app/vendor/quant-db-1.2.0/setup.py
from setuptools import setup, Extension

module = Extension('quant_db.aggregator',
                   sources=['quant_db/aggregator.c'],
                   include_dirs=['/usr/local/include/wrong_path']) # Missing -lm and wrong include path

setup(name='quant-db',
      version='1.2.0',
      description='Custom vendored data processing library',
      packages=['quant_db'],
      ext_modules=[module])
EOF

    # Create __init__.py
    cat << 'EOF' > /app/vendor/quant-db-1.2.0/quant_db/__init__.py
from .aggregator import aggregate
EOF

    # Create aggregator.c with precision bug
    cat << 'EOF' > /app/vendor/quant-db-1.2.0/quant_db/aggregator.c
#include <Python.h>
#include <math.h>

static PyObject* aggregate(PyObject* self, PyObject* args) {
    PyObject* listObj;
    if (!PyArg_ParseTuple(args, "O", &listObj)) {
        return NULL;
    }
    Py_ssize_t size = PyList_Size(listObj);
    float sum = 0.0f; // Naive float summation causes precision loss
    for (Py_ssize_t i = 0; i < size; i++) {
        PyObject* item = PyList_GetItem(listObj, i);
        if (!PyFloat_Check(item) && !PyLong_Check(item)) continue;
        sum += (float)PyFloat_AsDouble(item);
    }
    return PyFloat_FromDouble((double)sum);
}

static PyMethodDef AggregatorMethods[] = {
    {"aggregate", aggregate, METH_VARARGS, "Aggregate a list of floats."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef aggregatormodule = {
    PyModuleDef_HEAD_INIT,
    "aggregator",
    NULL,
    -1,
    AggregatorMethods
};

PyMODINIT_FUNC PyInit_aggregator(void) {
    return PyModule_Create(&aggregatormodule);
}
EOF

    # Create tests
    cat << 'EOF' > /app/vendor/quant-db-1.2.0/tests/test_agg.py
import pytest
from quant_db import aggregate

def test_aggregate_precision():
    # 10 million times 0.1 should be exactly 1,000,000.0
    # With naive float summation, it will drift significantly
    data = [0.1] * 10000000
    result = aggregate(data)
    assert abs(result - 1000000.0) < 0.01, f"Expected ~1000000.0, got {result}"
EOF

    # Generate WAL file and corpora
    python3 -c '
import struct
import json
import os

# Generate WAL
with open("/app/data/transaction.wal", "wb") as f:
    # Valid record 1
    p1 = json.dumps({"id": 1, "val": 100}).encode()
    f.write(struct.pack(">I", 0xDEADBEEF))
    f.write(struct.pack(">I", len(p1)))
    f.write(p1)

    # Corrupted segment
    f.write(b"garbage data that breaks things")

    # Valid record 2
    p2 = json.dumps({"id": 2, "val": 200}).encode()
    f.write(struct.pack(">I", 0xDEADBEEF))
    f.write(struct.pack(">I", len(p2)))
    f.write(p2)

# Generate Clean Corpus
with open("/app/corpus/clean/payload1.dat", "w") as f:
    f.write(json.dumps({"type": "telemetry", "data": 123}))
with open("/app/corpus/clean/payload2.dat", "w") as f:
    f.write(json.dumps({"type": "telemetry", "data": 456}))

# Generate Evil Corpus (structural anomalies)
with open("/app/corpus/evil/payload1.dat", "w") as f:
    f.write(json.dumps({"type": "telemetry", "data": {"__class__": "os.system"}}))
with open("/app/corpus/evil/payload2.dat", "w") as f:
    f.write(json.dumps({"type": "telemetry", "data": {"__class__": "subprocess.Popen"}}))
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
