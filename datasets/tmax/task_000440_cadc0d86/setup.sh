#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv python3-dev build-essential
    pip3 install pytest

    mkdir -p /home/user/fast-router/router
    mkdir -p /home/user/fast-router/tests

    cat << 'EOF' > /home/user/fast-router/router/__init__.py
EOF

    cat << 'EOF' > /home/user/fast-router/router/_fast_router.c
#include <Python.h>
static PyObject* get_version(PyObject* self, PyObject* args) { return Py_BuildValue("s", "1.0"); }
static PyMethodDef methods[] = { {"get_version", get_version, METH_VARARGS, ""}, {NULL, NULL, 0, NULL} };
static struct PyModuleDef module = { PyModuleDef_HEAD_INIT, "_fast_router", NULL, -1, methods };
PyMODINIT_FUNC PyInit__fast_router(void) { return PyModule_Create(&module); }
EOF

    cat << 'EOF' > /home/user/fast-router/router/parser.py
def parse_routing_table(data: str) -> dict:
    result = {}
    for line in data.split('\n'):
        k, v = line.split('=>')
        result[k.strip()] = v.strip()
    return result
EOF

    cat << 'EOF' > /home/user/fast-router/tests/test_parser.py
from router.parser import parse_routing_table

def test_parse():
    data = "/home => home-svc\n# comment\n\n/about => about-svc"
    res = parse_routing_table(data)
    assert res == {"/home": "home-svc", "/about": "about-svc"}
EOF

    cat << 'EOF' > /home/user/fast-router/tests/test_fetcher.py
import urllib.request
import json

def fetch_and_parse(url):
    with urllib.request.urlopen(url) as response:
        data = response.read().decode('utf-8')
    return json.loads(data)

def test_update_routes():
    res = fetch_and_parse("http://example.nonexistent.domain/routes.json")
    assert res == {"/api/v1": "backend-1", "/api/v2": "backend-2"}
EOF

    cat << 'EOF' > /home/user/fast-router/setup.py
from setuptools import setup, Extension
import os

ext = Extension('router._fast_router', sources=['router/_fast_router.c'])

setup(
    name='fast-router',
    version='0.1',
    packages=['router'],
    ext_modules=[ext],
)
EOF

    cd /home/user/fast-router
    python3 -m venv venv
    . venv/bin/activate
    pip install pytest

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
