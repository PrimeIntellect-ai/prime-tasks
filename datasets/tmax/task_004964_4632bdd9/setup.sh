#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        python3-dev \
        build-essential \
        imagemagick \
        tesseract-ocr

    pip3 install pytest flask psutil requests

    mkdir -p /home/user/img_service /app
    cd /home/user/img_service

    cat << 'EOF' > processor.c
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <stdint.h>

static PyObject* process_image(PyObject* self, PyObject* args) {
    PyObject* py_list;
    float multiplier;
    if (!PyArg_ParseTuple(args, "Of", &py_list, &multiplier)) {
        return NULL;
    }

    Py_ssize_t size = PyList_Size(py_list);
    int16_t sum = 0; // BUG: signed 16-bit integer overflow

    for (Py_ssize_t i = 0; i < size; i++) {
        PyObject* item = PyList_GetItem(py_list, i);
        long val = PyLong_AsLong(item);
        sum += (int16_t)(val * multiplier);
    }

    // BUG: creating a new float object but not returning it properly if we wrap it, 
    // or just a direct memory leak by leaking references if we allocate inside a loop.
    // Let's do a blatant memory leak:
    PyObject* leaked = PyList_New(100);
    for(int i=0; i<100; i++) PyList_SetItem(leaked, i, PyLong_FromLong(i));
    // Never decref 'leaked'

    float result = (float)sum / size;
    return Py_BuildValue("f", result);
}

static PyMethodDef ProcessorMethods[] = {
    {"process",  process_image, METH_VARARGS, "Process image data."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef processormodule = {
    PyModuleDef_HEAD_INIT,
    "processor",
    NULL,
    -1,
    ProcessorMethods
};

PyMODINIT_FUNC PyInit_processor(void) {
    return PyModule_Create(&processormodule);
}
EOF

    cat << 'EOF' > setup.py
from setuptools import setup, Extension
module1 = Extension('processor', sources = ['processor.c'])
setup(name = 'processor', version = '1.0', ext_modules = [module1])
EOF

    cat << 'EOF' > server.py
from flask import Flask, request, jsonify
import processor

app = Flask(__name__)

@app.route('/process', methods=['POST'])
def process_data():
    data = request.json
    pixels = data.get('pixels', [])
    multiplier = data.get('multiplier', 1.0)
    res = processor.process(pixels, multiplier)
    return jsonify({"result": res})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8000)
EOF

    # Generate bug_report.png
    convert -size 800x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 20,100 'The crash occurs when the intensity multiplier is set to 42.5'" /app/bug_report.png

    cat << 'EOF' > /app/verifier.py
import requests
import time
import os
import psutil

def get_memory_mb(pid):
    process = psutil.Process(pid)
    return process.memory_info().rss / (1024 * 1024)

def check():
    # Find server PID
    server_pid = None
    for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
        try:
            cmd = proc.cmdline()
            if 'python' in proc.name() and 'server.py' in ''.join(cmd):
                server_pid = proc.pid
                break
        except:
            pass

    if not server_pid:
        print("999.0")
        return

    # Check numerical correctness first
    test_pixels = [200] * 1000
    try:
        resp = requests.post('http://127.0.0.1:8000/process', json={"pixels": test_pixels, "multiplier": 42.5})
        res = resp.json()["result"]
        # Expected: 200 * 42.5 = 8500.0. If overflow (int16), it will be wrong.
        if abs(res - 8500.0) > 1.0:
            print("999.0") # Fails correctness
            return
    except Exception:
        print("999.0")
        return

    mem_before = get_memory_mb(server_pid)

    # Load test
    for _ in range(5000):
        requests.post('http://127.0.0.1:8000/process', json={"pixels": [100]*50, "multiplier": 1.0})

    mem_after = get_memory_mb(server_pid)
    leaked = mem_after - mem_before

    print(f"{leaked:.2f}")

if __name__ == "__main__":
    check()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
