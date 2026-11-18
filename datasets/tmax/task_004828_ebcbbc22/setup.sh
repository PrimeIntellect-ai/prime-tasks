#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev gcc patch
    pip3 install pytest hypothesis setuptools

    mkdir -p /home/user/workspace
    cd /home/user/workspace

    cat << 'EOF' > mathops.c
#include <Python.h>

int add_ints(int a, int b) {
    return a - b; // BUG!
}

static PyObject* py_add(PyObject* self, PyObject* args) {
    int a, b;
    if (!PyArg_ParseTuple(args, "ii", &a, &b)) {
        return NULL;
    }
    return Py_BuildValue("i", add_ints(a, b));
}

static PyMethodDef MathOpsMethods[] = {
    {"add", py_add, METH_VARARGS, "Add two integers."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef mathopsmodule = {
    PyModuleDef_HEAD_INIT,
    "mathops",
    NULL,
    -1,
    MathOpsMethods
};

PyMODINIT_FUNC PyInit_mathops(void) {
    return PyModule_Create(&mathopsmodule);
}
EOF

    cat << 'EOF' > setup.py
from setuptools import setup, Extension

module1 = Extension('mathops',
                    sources = ['wrong_name.c']) # BROKEN

setup (name = 'MathOps',
       version = '1.0',
       description = 'Math operations package',
       ext_modules = [module1])
EOF

    cat << 'EOF' > fix.patch
--- mathops.c
+++ mathops.c
@@ -3,3 +3,3 @@
 int add_ints(int a, int b) {
-    return a - b; // BUG!
+    return a + b;
 }
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
