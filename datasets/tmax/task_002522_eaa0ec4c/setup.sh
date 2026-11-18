#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev gcc make
    pip3 install pytest setuptools

    mkdir -p /app/legacy_router/legacy_router
    mkdir -p /app/legacy_router/src
    mkdir -p /app/training_corpus/clean
    mkdir -p /app/training_corpus/evil
    mkdir -p /app/hidden_corpus/clean
    mkdir -p /app/hidden_corpus/evil

    cat << 'EOF' > /app/legacy_router/setup.py
from setuptools import setup, Extension

ext_module = Extension(
    'legacy_router.ext',
    sources=['src/ext.c'],
)

setup(
    name='legacy_router',
    version='1.0.0',
    packages=['legacy_router'],
    ext_modules=[ext_module],
)
EOF

    cat << 'EOF' > /app/legacy_router/Makefile
CFLAGS=$(shell python-config --cflags)

all:
	gcc $(CFLAGS) -shared -fPIC -o legacy_router/ext.so src/ext.c
EOF

    cat << 'EOF' > /app/legacy_router/legacy_router/__init__.py
import parser

def parse_url(url):
    return parser.parse(url)
EOF

    cat << 'EOF' > /app/legacy_router/legacy_router/parser.py
import urllib.parse

def parse(url):
    parsed = urllib.parse.urlparse(url)
    return dict(urllib.parse.parse_qsl(parsed.query))
EOF

    cat << 'EOF' > /app/legacy_router/src/ext.c
#include <Python.h>

static PyModuleDef extmodule = {
    PyModuleDef_HEAD_INIT,
    "ext",
    "Extension module",
    -1,
    NULL
};

PyMODINIT_FUNC PyInit_ext(void) {
    return PyModule_Create(&extmodule);
}
EOF

    cat << 'EOF' > /app/training_corpus/clean/urls.txt
http://api.local/endpoint?bytecode=UkVBRCAvZGF0YS9wdWJsaWMvZm9vLnR4dA==
EOF

    cat << 'EOF' > /app/training_corpus/evil/urls.txt
http://api.local/endpoint?bytecode=RVhFQyBscw==
EOF

    cat << 'EOF' > /app/hidden_corpus/clean/urls.txt
http://api.local/endpoint?bytecode=UkVBRCAvZGF0YS9wdWJsaWMvaW1hZ2UucG5n
http://api.local/endpoint?bytecode=V1JJVEUgbG9jYWxfZmlsZS50eHQ=
http://api.local/endpoint?bytecode=UkVBRCAvZGF0YS9wdWJsaWMvZm9sZGVyL2ZpbGUudHh0fFdSSVRFIHNhdmVkX2RhdGE=
EOF

    cat << 'EOF' > /app/hidden_corpus/evil/urls.txt
http://api.local/endpoint?bytecode=RVhFQyBybSAtcmYgLw==
http://api.local/endpoint?bytecode=UkVBRCAvZXRjL3Bhc3N3ZA==
http://api.local/endpoint?bytecode=V1JJVEUgL2RhdGEvcHVibGljLy4uL3ByaXZhdGUva2V5
http://api.local/endpoint?bytecode=UkVBRCByZWxhdGl2ZS8uLi9wYXRo
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
