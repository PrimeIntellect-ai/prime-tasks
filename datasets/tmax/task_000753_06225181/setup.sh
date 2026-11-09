#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install pytest

    # Create vendored package
    mkdir -p /app/vendored/cypher-parser

    cat << 'EOF' > /app/vendored/cypher-parser/cypher_parser.cpp
#include <Python.h>

static PyObject* parse(PyObject* self, PyObject* args) {
    const char* query;
    if (!PyArg_ParseTuple(args, "s", &query)) return NULL;
    return Py_BuildValue("s", "AST_DUMMY");
}

static PyMethodDef methods[] = {
    {"parse", parse, METH_VARARGS, "Parse query"},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef module = {
    PyModuleDef_HEAD_INIT, "cypher_parser", NULL, -1, methods
};

PyMODINIT_FUNC PyInit_cypher_parser(void) {
    return PyModule_Create(&module);
}
EOF

    cat << 'EOF' > /app/vendored/cypher-parser/setup.py
from setuptools import setup, Extension
import os

cxxflags = os.environ.get("CXXFLAGS", "").split()

module = Extension('cypher_parser',
                   sources=['cypher_parser.cpp'],
                   extra_compile_args=cxxflags)

setup(name='cypher_parser',
      version='1.0.0-custom',
      ext_modules=[module])
EOF

    cat << 'EOF' > /app/vendored/cypher-parser/Makefile
CXXFLAGS = -O2

all:
	@echo "$(CXXFLAGS)" | grep -q -- "-std=c++11" || (echo "Error: -std=c++11 compiler flag is missing." && exit 1)
	CXXFLAGS="$(CXXFLAGS)" python3 setup.py install
EOF

    # Create corpora
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    cat << 'EOF' > /app/corpora/clean/query1.cypher
MATCH (n:Person) RETURN n.name, n.age LIMIT 10
EOF

    cat << 'EOF' > /app/corpora/clean/query2.cypher
MATCH (a:User)-[:KNOWS]->(b:User)
WHERE a.id = 123
RETURN b
EOF

    cat << 'EOF' > /app/corpora/evil/query1.cypher
MATCH (n) DETACH DELETE n
EOF

    cat << 'EOF' > /app/corpora/evil/query2.cypher
MATCH (a)-[*]->(b) RETURN a, b
EOF

    cat << 'EOF' > /app/corpora/evil/query3.cypher
MATCH (a), (b) RETURN a, b
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
