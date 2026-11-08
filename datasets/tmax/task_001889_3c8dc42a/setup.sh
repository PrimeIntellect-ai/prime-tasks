#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        python3-dev \
        build-essential \
        nginx \
        procps

    pip3 install pytest flask requests psutil setuptools

    mkdir -p /home/user/app/src
    mkdir -p /home/user/app/tests

    cat << 'EOF' > /home/user/app/src/fast_encode.c
#include <Python.h>
#include <stdlib.h>
#include <string.h>

static PyObject* fast_encode_process(PyObject* self, PyObject* args) {
    const char* input;
    if (!PyArg_ParseTuple(args, "s", &input)) {
        return NULL;
    }

    // memory leak here
    char* copy = malloc(strlen(input) + 1);
    strcpy(copy, input);

    for(int i=0; i<strlen(copy); i++) {
        copy[i] = copy[i] + 1;
    }

    PyObject* result = Py_BuildValue("s", copy);
    // Missing free(copy);

    return result;
}

static PyMethodDef FastEncodeMethods[] = {
    {"process", fast_encode_process, METH_VARARGS, "Process string"},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fastencodemodule = {
    PyModuleDef_HEAD_INIT,
    "fast_encode",
    NULL,
    -1,
    FastEncodeMethods
};

PyMODINIT_FUNC PyInit_fast_encode(void) {
    return PyModule_Create(&fastencodemodule);
}
EOF

    cat << 'EOF' > /home/user/app/setup.py
from setuptools import setup, Extension
module = Extension('fast_encode', sources=['src/fast_encode.c'])
setup(name='fast_encode', version='1.0', ext_modules=[module])
EOF

    cat << 'EOF' > /home/user/app/app.py
from flask import Flask, request, jsonify
import fast_encode

app = Flask(__name__)

@app.route('/encode', methods=['GET'])
def encode():
    text = request.args.get('text', '')
    res = fast_encode.process(text)
    return jsonify({"result": res})

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /home/user/app/nginx.conf
worker_processes 1;
events { worker_connections 1024; }
http {
    server {
        listen 8080;
        location / {
            return 404;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/app/tests/test_api.py
import unittest

class TestAPI(unittest.TestCase):
    def test_encode(self):
        pass
EOF

    cat << 'EOF' > /home/user/app/load_test.py
import requests
import time
import json
import psutil
import subprocess

def run_load_test():
    try:
        pids = subprocess.check_output(["pgrep", "-f", "app.py"]).decode().strip().split()
        flask_pid = int(pids[0])
        process = psutil.Process(flask_pid)
    except Exception:
        print(json.dumps({"requests_per_second": 0, "memory_growth_mb": 100.0}))
        return

    try:
        requests.get("http://127.0.0.1:8080/encode?text=test", timeout=1)
    except Exception:
        print(json.dumps({"requests_per_second": 0, "memory_growth_mb": 100.0}))
        return

    start_mem = process.memory_info().rss
    start_time = time.time()

    reqs = 10000
    for _ in range(reqs):
        try:
            requests.get("http://127.0.0.1:8080/encode?text=test1234567890", timeout=1)
        except Exception:
            break

    end_time = time.time()
    end_mem = process.memory_info().rss

    duration = end_time - start_time
    tps = reqs / duration if duration > 0 else 0
    mem_growth = (end_mem - start_mem) / (1024 * 1024)

    print(json.dumps({"requests_per_second": tps, "memory_growth_mb": mem_growth}))

if __name__ == "__main__":
    run_load_test()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/app
    chmod -R 777 /home/user
