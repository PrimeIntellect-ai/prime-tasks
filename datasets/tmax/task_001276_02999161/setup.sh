#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install pytest hypothesis setuptools

    mkdir -p /home/user/rate_limiter

    cat << 'EOF' > /home/user/rate_limiter/bucket.c
#include <Python.h>

static PyObject* consume(PyObject* self, PyObject* args) {
    long tokens, elapsed, capacity, fill_rate, current_tokens;
    if (!PyArg_ParseTuple(args, "lllll", &tokens, &elapsed, &capacity, &fill_rate, &current_tokens))
        return NULL;

    current_tokens += elapsed * fill_rate;
    if (current_tokens > capacity) {
        current_tokens = capacity;
    }

    if (current_tokens >= tokens) {
        current_tokens -= tokens;
        return Py_BuildValue("(il)", 1, current_tokens);
    } else {
        return Py_BuildValue("(il)", 0, current_tokens);
    }
}

static PyMethodDef BucketMethods[] = {
    {"consume",  consume, METH_VARARGS, "Consume tokens."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef bucketmodule = {
    PyModuleDef_HEAD_INIT, "_bucket", NULL, -1, BucketMethods
};

PyMODINIT_FUNC PyInit__bucket(void) {
    return PyModule_Create(&bucketmodule);
}
EOF

    cat << 'EOF' > /home/user/rate_limiter/limiter.py
import _bucket

class TokenBucket:
    def __init__(self, capacity, fill_rate):
        self.capacity = capacity
        self.fill_rate = fill_rate
        self.tokens = capacity

    def consume(self, tokens, elapsed):
        success, new_tokens = _bucket.consume(tokens, elapsed, self.capacity, self.fill_rate, self.tokens)
        self.tokens = new_tokens
        return bool(success)

    def get_tokens(self):
        return self.tokens
EOF

    cat << 'EOF' > /home/user/rate_limiter/setup.py
from setuptools import setup, Extension

# FIXME: The extension module is named incorrectly and missing the source file
module = Extension('wrong_name', sources=[])

setup(
    name='RateLimiter',
    version='1.0',
    ext_modules=[module]
)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
