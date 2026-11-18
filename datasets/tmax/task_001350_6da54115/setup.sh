#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev gcc gdb tesseract-ocr
    pip3 install pytest Pillow

    # Create app directory
    mkdir -p /app

    # Generate equation image
    cat << 'EOF' > /tmp/gen_img.py
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), "f(x) = 4x^3 + 7x^2 - 2x + 9", fill=(0, 0, 0))
img.save('/app/equation.png')
EOF
    python3 /tmp/gen_img.py

    # Create oracle
    cat << 'EOF' > /app/oracle_eval
#!/usr/bin/env python3
import sys
x = int(sys.argv[1])
print(4*x**3 + 7*x**2 - 2*x + 9)
EOF
    chmod +x /app/oracle_eval

    # Create math_service directory
    mkdir -p /home/user/math_service

    # Create buggy setup.py
    cat << 'EOF' > /home/user/math_service/setup.py
from setuptools import setup, Extension

module1 = Extension('math_ext',
                    sources = ['math_ext.c']
                    # missing comma
                    extra_compile_args = ['-O3']
                    )

setup (name = 'MathExt',
       version = '1.0',
       description = 'Math package' # missing comma
       ext_modules = [module1])
EOF

    # Create buggy C-extension
    cat << 'EOF' > /home/user/math_service/math_ext.c
#include <Python.h>
#include <stdio.h>
#include <stdlib.h>

static PyObject* evaluate(PyObject* self, PyObject* args) {
    int x;
    if (!PyArg_ParseTuple(args, "i", &x)) return NULL;
    int buffer[10];
    if (x > 100) {
        for(int i=0; i<x; i++) buffer[i] = i; // buffer overflow
    }
    return PyLong_FromLong(4*x*x*x + 7*x*x - 2*x + 9);
}

static PyMethodDef MathMethods[] = {
    {"evaluate",  evaluate, METH_VARARGS, "Evaluate polynomial."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef mathmodule = {
    PyModuleDef_HEAD_INIT, "math_ext", NULL, -1, MathMethods
};

PyMODINIT_FUNC PyInit_math_ext(void) {
    return PyModule_Create(&mathmodule);
}
EOF

    # Create a dummy core dump (generating real core dump in build env is unreliable)
    echo "ELF... core dump... buffer overflow at evaluate()" > /home/user/math_service/core.dump

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
