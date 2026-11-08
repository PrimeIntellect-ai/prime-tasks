#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev python3-setuptools gcc build-essential
    pip3 install pytest

    mkdir -p /home/user/legacy_project
    cd /home/user/legacy_project

    cat << 'EOF' > fastcalc.c
#include <Python.h>
#include <stdlib.h>

static PyObject* calculate_metric(PyObject* self, PyObject* args) {
    PyObject *listObj;
    if (!PyArg_ParseTuple(args, "O!", &PyList_Type, &listObj)) {
        return NULL;
    }

    Py_ssize_t size = PyList_Size(listObj);
    if (size == 0) {
        return PyFloat_FromDouble(0.0);
    }

    double *arr = (double*)malloc(size * sizeof(double));

    // BUG 1: Off-by-one error (i <= size instead of i < size) causing UB/segfault
    for (Py_ssize_t i = 0; i <= size; i++) {
        PyObject* item = PyList_GetItem(listObj, i);
        if (item) {
            arr[i] = PyFloat_AsDouble(item);
        }
    }

    double sum = 0;
    for (Py_ssize_t i = 0; i < size; i++) {
        sum += arr[i];
    }

    // BUG 2: Memory leak (missing free(arr))

    // Python 2 specific return type
    return PyFloat_FromDouble(sum / size);
}

static PyMethodDef FastCalcMethods[] = {
    {"calculate_metric", calculate_metric, METH_VARARGS, "Calculate metric from list"},
    {NULL, NULL, 0, NULL}
};

// Python 2 specific module initialization
PyMODINIT_FUNC initfastcalc(void) {
    (void) Py_InitModule("fastcalc", FastCalcMethods);
}
EOF

    cat << 'EOF' > Makefile
all:
	gcc -shared -o fastcalc.so -I/usr/include/python2.7 -fPIC fastcalc.c
EOF

    cat << 'EOF' > process.py
import fastcalc

def main():
    # Python 2 xrange
    data = [float(i) for i in xrange(1, 11)]
    result = fastcalc.calculate_metric(data)
    # Python 2 print
    print "Computed Metric:", result

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/legacy_project
    chmod -R 777 /home/user
