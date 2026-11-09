#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    mkdir -p /app/fast_log_tokenizer-0.1

    cat << 'EOF' > /app/fast_log_tokenizer-0.1/setup.py
from setuptools import setup, Extension
module1 = Extension('fast_log_tokenizer', sources = ['fast_tokenizer.c'])
setup(name = 'fast_log_tokenizer', version = '0.1', description = 'Tokenizer', ext_modules = [module1])
EOF

    cat << 'EOF' > /app/fast_log_tokenizer-0.1/tokenizer.c
#include <Python.h>
static PyObject* tokenize(PyObject* self, PyObject* args) {
    const char* text;
    if (!PyArg_ParseTuple(args, "s", &text)) return NULL;
    PyObject* list = PyList_New(0);
    // Dummy simple tokenizer splitting by space
    char* str = strdup(text);
    char* token = strtok(str, " ");
    while (token != NULL) {
        PyObject* py_token = PyUnicode_FromString(token);
        PyList_Append(list, py_token);
        Py_DECREF(py_token);
        token = strtok(NULL, " ");
    }
    free(str);
    return list;
}
static PyMethodDef Methods[] = {
    {"tokenize", tokenize, METH_VARARGS, "Tokenize text"},
    {NULL, NULL, 0, NULL}
};
static struct PyModuleDef module = {
    PyModuleDef_HEAD_INIT, "fast_log_tokenizer", NULL, -1, Methods
};
PyMODINIT_FUNC PyInit_fast_log_tokenizer(void) {
    return PyModule_Create(&module);
}
EOF

    cat << 'EOF' > /tmp/generate.py
import os
import json
import random
from datetime import datetime, timedelta

random.seed(42)
langs = ['en', 'es', 'fr', 'de', 'zh']
weights = [0.5, 0.2, 0.1, 0.1, 0.1]

with open("/home/user/raw_logs.jsonl", "w") as f:
    for i in range(10000):
        lang = random.choices(langs, weights=weights)[0]
        dt = datetime(2023, 1, 1) + timedelta(minutes=i)

        fmt_choice = random.randint(0, 3)
        if fmt_choice == 0:
            ts = dt.timestamp()
        elif fmt_choice == 1:
            ts = dt.timestamp() * 1000
        elif fmt_choice == 2:
            ts = dt.strftime("%Y/%m/%d %H:%M:%S")
        else:
            ts = dt.isoformat() + "Z"

        msg = f"Hello {lang} World {i}   with extra spaces"
        record = {"id": i, "timestamp": ts, "lang": lang, "msg": msg}
        f.write(json.dumps(record) + "\n")
EOF

    python3 /tmp/generate.py
    rm /tmp/generate.py

    chmod -R 777 /app
    chmod -R 777 /home/user
