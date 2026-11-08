#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install pytest setuptools

    mkdir -p /app/vendored/py-fast-distance
    mkdir -p /home/user

    cat << 'EOF' > /app/vendored/py-fast-distance/fast_distance.c
#include <Python.h>
#include <math.h>

static PyObject* fast_distance_compute(PyObject* self, PyObject* args) {
    double lat, lon;
    if (!PyArg_ParseTuple(args, "dd", &lat, &lon)) {
        return NULL;
    }
    double res = sqrt(pow(lat, 2) + pow(lon, 2));
    return PyFloat_FromDouble(res);
}

static PyMethodDef FastDistanceMethods[] = {
    {"compute", fast_distance_compute, METH_VARARGS, "Compute distance."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fastdistancemodule = {
    PyModuleDef_HEAD_INIT,
    "fast_distance",
    NULL,
    -1,
    FastDistanceMethods
};

PyMODINIT_FUNC PyInit_fast_distance(void) {
    return PyModule_Create(&fastdistancemodule);
}
EOF

    cat << 'EOF' > /app/vendored/py-fast-distance/setup.py
from setuptools import setup, Extension

module = Extension('fast_distance', sources=['fast_distance.c'])

setup(
    name='py-fast-distance',
    version='1.0.0',
    ext_modules=[module]
)
EOF

    cat << 'EOF' > /home/user/pipeline.py
import sqlite3
import sys
import fast_distance

def main():
    if len(sys.argv) != 2:
        sys.exit(1)
    db_path = sys.argv[1]
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    # Broken query
    cur.execute("SELECT s.id, s.lat, s.lon, c.factor FROM sensors s LEFT JOIN calibration c ON s.id = c.sensor_id ORDER BY s.id ASC")
    for row in cur.fetchall():
        sensor_id, lat, lon, factor = row
        if factor is None:
            factor = 1.0
        dist = fast_distance.compute(lat, lon)
        # Broken formula
        score = dist + factor
        print(f"{score:.4f}")

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > /app/oracle_pipeline.py
import sqlite3
import sys
import math

def compute(lat, lon):
    return math.sqrt(math.pow(lat, 2) + math.pow(lon, 2))

def main():
    if len(sys.argv) != 2:
        sys.exit(1)
    db_path = sys.argv[1]
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute("SELECT s.id, s.lat, s.lon, c.factor FROM sensors s INNER JOIN calibration c ON s.id = c.sensor_id WHERE s.status = 'ACTIVE' ORDER BY s.id ASC")
    for row in cur.fetchall():
        sensor_id, lat, lon, factor = row
        dist = compute(lat, lon)
        score = dist * factor
        print(f"{score:.4f}")

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
