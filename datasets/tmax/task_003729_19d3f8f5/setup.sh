#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        python3-dev \
        build-essential \
        redis-server \
        nginx

    pip3 install pytest fastapi uvicorn redis setuptools

    mkdir -p /home/user/workspace/api
    mkdir -p /home/user/workspace/nginx
    mkdir -p /home/user/workspace/corpus/clean
    mkdir -p /home/user/workspace/corpus/evil

    cat << 'EOF' > /home/user/workspace/api/setup.py
from setuptools import setup, Extension
# MISSING INCLUDE DIRS and broken compile args
module1 = Extension('fastparser',
                    sources = ['fastparser.c'])

setup (name = 'fastparser',
       version = '1.0',
       description = 'Broken package',
       ext_modules = [module1])
EOF

    cat << 'EOF' > /home/user/workspace/api/fastparser.c
#include <Python.h>

static PyObject* fastparser_parse(PyObject* self, PyObject* args) {
    const char* payload;
    if (!PyArg_ParseTuple(args, "s", &payload)) {
        return NULL;
    }
    return Py_BuildValue("s", payload);
}

static PyMethodDef FastParserMethods[] = {
    {"parse", fastparser_parse, METH_VARARGS, "Parse payload."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fastparsermodule = {
    PyModuleDef_HEAD_INIT,
    "fastparser",
    NULL,
    -1,
    FastParserMethods
};

PyMODINIT_FUNC PyInit_fastparser(void) {
    return PyModule_Create(&fastparsermodule);
}
EOF

    cat << 'EOF' > /home/user/workspace/api/main.py
from fastapi import FastAPI, Request
import os
import subprocess
import tempfile
import redis

app = FastAPI()
r = redis.Redis.from_url(os.environ.get("REDIS_URL", "redis://127.0.0.1:6379/0"))

@app.post("/submit")
async def submit(request: Request):
    body = await request.body()

    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        tmp.write(body)
        tmp_path = tmp.name

    classifier_cmd = os.environ.get("CLASSIFIER_CMD")
    if not classifier_cmd:
        return {"status": "error", "message": "CLASSIFIER_CMD not set"}

    result = subprocess.run([classifier_cmd, tmp_path], capture_output=True)
    os.remove(tmp_path)

    if result.returncode == 0:
        r.incr("clean_payloads")
        return {"status": "clean"}
    else:
        r.incr("evil_payloads")
        return {"status": "evil"}
EOF

    cat << 'EOF' > /home/user/workspace/nginx/nginx.conf
events {}
http {
    server {
        # listen 8080;
        # location / {
        #     proxy_pass http://127.0.0.1:5000;
        # }
    }
}
EOF

    echo -n "user=admin\ncmd=status" > /home/user/workspace/corpus/clean/01.txt
    echo -n "data=hello\x20world" > /home/user/workspace/corpus/clean/02.txt

    echo -n "cmd=EXEC_PAYLOAD" > /home/user/workspace/corpus/evil/01.txt
    echo -n "cmd=\x45XEC_PAYLOAD" > /home/user/workspace/corpus/evil/02.txt
    echo -n "query=DROP_DB" > /home/user/workspace/corpus/evil/03.txt
    echo -n "query=DR\x4fP_DB" > /home/user/workspace/corpus/evil/04.txt

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
