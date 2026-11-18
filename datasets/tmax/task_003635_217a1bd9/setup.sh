#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev gcc git imagemagick tesseract-ocr
    pip3 install pytest setuptools

    mkdir -p /app

    # Generate image
    # Note: imagemagick policy might prevent some operations, but simple text drawing usually works.
    convert -size 600x200 xc:white -fill black -pointsize 32 -gravity center -draw "text 0,0 'CRITICAL SYSTEM SALT: 839201'" /app/sys_monitor.png

    # Setup git repo
    mkdir -p /app/math_parser_repo
    cd /app/math_parser_repo
    git init
    git config user.email "devops@example.com"
    git config user.name "DevOps"

    cat << 'EOF' > math_parser.c
#include <Python.h>

static PyObject* compute_hash(PyObject* self, PyObject* args) {
    long long query_value;
    long long salt;
    if (!PyArg_ParseTuple(args, "LL", &query_value, &salt)) {
        return NULL;
    }
    long long result = (query_value * salt) % 999983;
    return PyLong_FromLongLong(result);
}

static PyMethodDef MathParserMethods[] = {
    {"compute_hash",  compute_hash, METH_VARARGS, "Compute hash."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef math_parser_module = {
    PyModuleDef_HEAD_INIT,
    "math_parser",
    NULL,
    -1,
    MathParserMethods
};

PyMODINIT_FUNC PyInit_math_parser(void) {
    return PyModule_Create(&math_parser_module);
}
EOF

    cat << 'EOF' > setup.py
from setuptools import setup, Extension

module1 = Extension('math_parser',
                    sources = ['math_parser.c'])

setup (name = 'MathParser',
       version = '1.0',
       description = 'This is a math parser package',
       ext_modules = [module1])
EOF

    git add math_parser.c setup.py
    git commit -m "Initial commit: working math parser"

    echo "// added some comments" >> math_parser.c
    git commit -am "Add comments"

    # Introduce bug
    sed -i 's/query_value \* salt/query_value + salt/g' math_parser.c
    git commit -am "Refactor hash computation"

    # Break build
    sed -i "s/sources = \['math_parser.c'\]/sources = \['math_parser.c'\], include_dirs=\['\/invalid\/path\/that\/breaks\/gcc'\]/g" setup.py
    git commit -am "Update setup.py include dirs"

    # Setup corpus
    mkdir -p /app/corpus/clean /app/corpus/evil
    python3 -c "
import json
import os
salt = 839201
for i in range(20):
    qv = i * 13 + 7
    with open(f'/app/corpus/clean/log_{i}.json', 'w') as f:
        json.dump({'query_value': qv, 'reported_hash': (qv * salt) % 999983}, f)
    with open(f'/app/corpus/evil/log_{i}.json', 'w') as f:
        json.dump({'query_value': qv, 'reported_hash': (qv * salt + 1) % 999983}, f)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
