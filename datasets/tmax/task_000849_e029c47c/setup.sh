#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-dev gcc build-essential

# Use longer timeout and retries to avoid ReadTimeoutError
pip3 install --default-timeout=100 --retries=5 pytest setuptools numpy scipy pandas

mkdir -p /app/libdist
mkdir -p /app/data/clean
mkdir -p /app/data/evil

# Create integrator C source
cat << 'EOF' > /app/integrator.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

double rand_normal() {
    double u1 = ((double) rand() / RAND_MAX);
    double u2 = ((double) rand() / RAND_MAX);
    if (u1 <= 0.0) u1 = 1e-5;
    return sqrt(-2.0 * log(u1)) * cos(2.0 * M_PI * u2);
}

int main(int argc, char *argv[]) {
    if (argc != 3) return 1;
    FILE *fin = fopen(argv[1], "r");
    if (!fin) return 1;
    int type = 0;
    fscanf(fin, "%d", &type);
    fclose(fin);

    FILE *fout = fopen(argv[2], "w");
    if (!fout) return 1;
    for (int i = 0; i < 1000; i++) {
        double val = rand_normal();
        if (type == 1) {
            val *= (1.0 + i * 0.05); // variance explodes
        }
        fprintf(fout, "%f\n", val);
    }
    fclose(fout);
    return 0;
}
EOF

# Compile and strip the binary
gcc -O2 /app/integrator.c -o /app/integrator_bin -lm
strip /app/integrator_bin
rm /app/integrator.c

# Create libdist C extension source
cat << 'EOF' > /app/libdist/dist.c
#define PY_SSIZE_T_CLEAN
#include <Python.h>

static PyObject* compute_distance(PyObject* self, PyObject* args) {
    PyObject *list1, *list2;
    if (!PyArg_ParseTuple(args, "OO", &list1, &list2)) {
        return NULL;
    }
    Py_ssize_t len1 = PyList_Size(list1);
    Py_ssize_t len2 = PyList_Size(list2);
    double sum1 = 0, sum2 = 0;
    for (Py_ssize_t i = 0; i < len1; i++) {
        PyObject* item = PyList_GetItem(list1, i);
        if (PyFloat_Check(item)) sum1 += PyFloat_AsDouble(item);
        else if (PyLong_Check(item)) sum1 += PyLong_AsDouble(item);
    }
    for (Py_ssize_t i = 0; i < len2; i++) {
        PyObject* item = PyList_GetItem(list2, i);
        if (PyFloat_Check(item)) sum2 += PyFloat_AsDouble(item);
        else if (PyLong_Check(item)) sum2 += PyLong_AsDouble(item);
    }
    double mean1 = len1 > 0 ? sum1 / len1 : 0;
    double mean2 = len2 > 0 ? sum2 / len2 : 0;
    double diff = mean1 - mean2;
    if (diff < 0) diff = -diff;
    return PyFloat_FromDouble(diff);
}

static PyMethodDef DistMethods[] = {
    {"compute_distance", compute_distance, METH_VARARGS, "Compute distance"},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef distmodule = {
    PyModuleDef_HEAD_INIT,
    "libdist",
    NULL,
    -1,
    DistMethods
};

PyMODINIT_FUNC PyInit_libdist(void) {
    return PyModule_Create(&distmodule);
}
EOF

# Create setup.py for libdist
cat << 'EOF' > /app/libdist/setup.py
from setuptools import setup, Extension

module1 = Extension('libdist', sources = ['dist.c'])

setup (name = 'libdist',
       version = '1.0',
       description = 'Distance metric',
       ext_modules = [module1])
EOF

# Create clean and evil corpora
for i in $(seq 1 5); do
    echo "0" > /app/data/clean/clean_$i.csv
    echo "1" > /app/data/evil/evil_$i.csv
done

useradd -m -s /bin/bash user || true
chmod -R 777 /app
chmod -R 777 /home/user
