#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install pytest websockets

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/math_server/src

    cat << 'EOF' > /home/user/math_server/src/fastmath.c
#include <Python.h>

int collatz_steps(long long n) {
    int steps = 0;
    while (n > 1) {
#ifdef USE_OPTIMIZED
        if ((n & 1) == 0) {
            n >>= 1; // Correct
        } else {
            n = 3 * n - 1; // BUG: should be + 1
        }
#else
        if (n % 2 == 0) {
            n = n / 2;
        } else {
            n = 3 * n + 1;
        }
#endif
        steps++;
    }
    return steps;
}

static PyObject* py_collatz(PyObject* self, PyObject* args) {
    long long n;
    if (!PyArg_ParseTuple(args, "L", &n)) {
        return NULL;
    }
    int result = collatz_steps(n);
    return PyLong_FromLong(result);
}

static PyMethodDef FastMathMethods[] = {
    {"collatz", py_collatz, METH_VARARGS, "Calculate Collatz steps."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fastmathmodule = {
    PyModuleDef_HEAD_INIT,
    "fastmath",
    NULL,
    -1,
    FastMathMethods
};

PyMODINIT_FUNC PyInit_fastmath(void) {
    return PyModule_Create(&fastmathmodule);
}
EOF

    cat << 'EOF' > /home/user/math_server/setup.py
from setuptools import setup, Extension
import os

# Missing conditional logic for ENABLE_OPT
# Missing install_requires

module1 = Extension('fastmath', sources = ['src/fastmath.c'])

setup(name = 'FastMath',
      version = '1.0',
      description = 'Fast math package',
      ext_modules = [module1])
EOF

    cat << 'EOF' > /home/user/math_server/server.py
import asyncio
import websockets
import fastmath

async def handler(websocket, path):
    async for message in websocket:
        # Missing validation
        val = int(message)
        res = fastmath.collatz(val)
        await websocket.send(str(res))

start_server = websockets.serve(handler, "localhost", 8765)
asyncio.get_event_loop().run_until_complete(start_server)
asyncio.get_event_loop().run_forever()
EOF

    chmod -R 777 /home/user
