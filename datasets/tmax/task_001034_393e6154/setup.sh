#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        python3-dev \
        python3-setuptools \
        sqlite3 \
        gcc \
        make \
        curl \
        bash

    pip3 install pytest

    mkdir -p /app/waf-service/vendor/http-parser-ext
    mkdir -p /app/waf-service/db

    cat << 'EOF' > /app/waf-service/db/schema_v1.sql
CREATE TABLE signatures (
    id INTEGER PRIMARY KEY,
    pattern TEXT NOT NULL
);
EOF

    cat << 'EOF' > /app/waf-service/build.sh
#!/bin/bash
cd vendor/http-parser-ext
make
python setup.py install
EOF
    chmod +x /app/waf-service/build.sh

    cat << 'EOF' > /app/waf-service/server.py
import sys
import urllib2
import socket
import http_parser_ext

def run_server():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', 8443))
    s.listen(1)
    print "Listening on 127.0.0.1:8443..."

    while True:
        conn, addr = s.accept()
        data = conn.recv(1024)
        if data:
            # dummy state machine
            d = {'status': 'WAF Active'}
            for k, v in d.iteritems():
                pass
            response = "HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nWAF Active"
            conn.sendall(response.encode('utf-8') if sys.version_info[0] > 2 else response)
        conn.close()

if __name__ == '__main__':
    run_server()
EOF

    cat << 'EOF' > /app/waf-service/vendor/http-parser-ext/Makefile
all:
	@echo "Building..."

PYTHON_INCLUDES = $(shell python2-config --cflags)
PYTHON_LDFLAGS = $(shell python2-config --ldflags)
EOF

    cat << 'EOF' > /app/waf-service/vendor/http-parser-ext/setup.py
from setuptools import setup, Extension

module1 = Extension('http_parser_ext',
                    sources = ['http_parser_ext.c'])

setup (name = 'http_parser_ext',
       version = '1.0.0',
       description = 'HTTP parser C extension',
       ext_modules = [module1])
EOF

    cat << 'EOF' > /app/waf-service/vendor/http-parser-ext/http_parser_ext.c
#include <Python.h>

static PyObject* parse_request(PyObject* self, PyObject* args) {
    Py_RETURN_NONE;
}

static PyMethodDef HttpParserMethods[] = {
    {"parse_request", parse_request, METH_VARARGS, "Parse HTTP request."},
    {NULL, NULL, 0, NULL}
};

#if PY_MAJOR_VERSION >= 3
static struct PyModuleDef httpparsermodule = {
    PyModuleDef_HEAD_INIT,
    "http_parser_ext",
    NULL,
    -1,
    HttpParserMethods
};

PyMODINIT_FUNC PyInit_http_parser_ext(void) {
    return PyModule_Create(&httpparsermodule);
}
#else
PyMODINIT_FUNC inithttp_parser_ext(void) {
    Py_InitModule("http_parser_ext", HttpParserMethods);
}
#endif
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
