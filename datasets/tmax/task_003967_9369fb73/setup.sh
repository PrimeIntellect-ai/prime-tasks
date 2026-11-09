#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential curl nginx
pip3 install pytest

mkdir -p /home/user/app

cat << 'EOF' > /home/user/app/requirements.txt
fastapi==0.103.1
uvicorn==0.23.2
requests==2.31.0
EOF

cat << 'EOF' > /home/user/app/processor.c
#include <Python.h>

static PyObject* process_text(PyObject* self, PyObject* args) {
    const char* input;
    if (!PyArg_ParseTuple(args, "s", &input)) {
        return NULL;
    }
    return Py_BuildValue("s", "processed");
}

static PyMethodDef ProcessorMethods[] = {
    {"process", process_text, METH_VARARGS, "Process some text."},
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

cat << 'EOF' > /home/user/app/setup.py
from setuptools import setup, Extension

module1 = Extension('processor', sources=['processor.c'])

setup(
    name='processor',
    version='1.0',
    description='Text processor',
    ext_modules=[module1]
)
EOF

cat << 'EOF' > /home/user/app/main.py
import processor
import requests
from fastapi import FastAPI

app = FastAPI()

@app.get("/fetch")
def fetch_url(url: str):
    resp = requests.get(url)
    return {"content": processor.process(resp.text)}
EOF

cat << 'EOF' > /home/user/security_fix.patch
--- main.py
+++ main.py
@@ -1,5 +1,6 @@
+from urllib.parse import urlparse
 import requests
 from fastapi import FastAPI
 import processor

 app = FastAPI()

@@ -8,4 +9,6 @@
 def fetch_url(url: str):
+    if urlparse(url).hostname in ['localhost', '127.0.0.1']:
+        return {"error": "SSRF blocked"}
     resp = requests.get(url)
     return {"content": processor.process(resp.text)}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
