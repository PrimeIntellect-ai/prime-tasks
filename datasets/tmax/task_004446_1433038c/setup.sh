#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv python3-dev build-essential
    pip3 install pytest

    mkdir -p /home/user/pipeline

    cat << 'EOF' > /home/user/pipeline/fast_counter.c
#include <Python.h>

static PyObject* count_words(PyObject* self, PyObject* args) {
    const char* str;
    if (!PyArg_ParseTuple(args, "s", &str)) {
        return NULL;
    }

    long count = 0;
    int in_word = 0;
    const char* p = str;

    while (*p) {
        if (*p == ' ' || *p == '\t' || *p == '\n') {
            in_word = 0;
        } else if (!in_word) {
            in_word = 1;
            count++;
        }
        p++;
    }

    /* Legacy Python 2 C API return */
    return PyInt_FromLong(count);
}

static PyMethodDef WordMethods[] = {
    {"count_words", count_words, METH_VARARGS, "Count words in a string."},
    {NULL, NULL, 0, NULL}
};

/* Legacy Python 2 Module Initialization */
PyMODINIT_FUNC initword_counter(void) {
    Py_InitModule("word_counter", WordMethods);
}
EOF

    cat << 'EOF' > /home/user/pipeline/process.py
import word_counter

data = [
    "Hello world",
    "This is a migration test for Python 3",
    "   Multiple    spaces   should be   handled  ",
    ""
]

total_words = 0
for line in data:
    total_words += word_counter.count_words(line)

print(f"Migration successful! Total words processed: {total_words}")
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/pipeline
    chmod -R 777 /home/user
