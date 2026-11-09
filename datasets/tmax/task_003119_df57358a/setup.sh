#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential nginx curl
    pip3 install pytest flask setuptools

    mkdir -p /home/user/app/lib
    mkdir -p /home/user/app/src

    # Create processor.c
    cat << 'EOF' > /home/user/app/src/processor.c
int multiply_by_two(int x) {
    return x * 2;
}
EOF

    # Compile libprocessor.so
    gcc -shared -o /home/user/app/lib/libprocessor.so -fPIC /home/user/app/src/processor.c

    # Create pyprocessor.c
    cat << 'EOF' > /home/user/app/src/pyprocessor.c
#include <Python.h>

extern int multiply_by_two(int);

static PyObject* py_multiply_by_two(PyObject* self, PyObject* args) {
    int val;
    if (!PyArg_ParseTuple(args, "i", &val)) {
        return NULL;
    }
    return PyLong_FromLong(multiply_by_two(val));
}

static PyMethodDef PyprocessorMethods[] = {
    {"multiply_by_two", py_multiply_by_two, METH_VARARGS, "Multiply a number by two."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef pyprocessormodule = {
    PyModuleDef_HEAD_INIT,
    "pyprocessor",
    NULL,
    -1,
    PyprocessorMethods
};

PyMODINIT_FUNC PyInit_pyprocessor(void) {
    return PyModule_Create(&pyprocessormodule);
}
EOF

    # Create setup.py (missing library_dirs and runtime_library_dirs)
    cat << 'EOF' > /home/user/app/setup.py
from setuptools import setup, Extension

module = Extension('pyprocessor',
                   sources=['src/pyprocessor.c'],
                   libraries=['processor'])

setup(name='pyprocessor',
      version='1.0',
      ext_modules=[module])
EOF

    # Create app.py with broken state machine logic
    cat << 'EOF' > /home/user/app/app.py
from flask import Flask, jsonify
import pyprocessor

app = Flask(__name__)

def parse_data(filepath):
    total = 0
    state = "IDLE"
    with open(filepath, "r") as f:
        for line in f:
            line = line.strip()
            if line == "START":
                state = "IDLE" # Bug: should be "RECORDING"
            elif line == "STOP":
                state = "IDLE"
            elif line.startswith("VAL ") and state == "RECORDING":
                val = int(line.split()[1])
                total += pyprocessor.multiply_by_two(val)
    return total

@app.route('/process', methods=['GET'])
def process():
    total = parse_data("/home/user/app/data.txt")
    return jsonify({"result": total})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=9000)
EOF

    # Create data.txt
    cat << 'EOF' > /home/user/app/data.txt
VAL 5
START
VAL 10
VAL 15
STOP
VAL 20
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/app
    chmod -R 777 /home/user
