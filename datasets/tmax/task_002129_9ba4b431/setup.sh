#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential valgrind xxd binutils
    pip3 install pytest setuptools

    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.cpp
#include <iostream>
#include <vector>
#include <queue>
#include <string>

using namespace std;

int main() {
    char magic[4];
    if (cin.read(magic, 4).gcount() != 4 || string(magic, 4) != "GRPH") {
        cout << "INVALID_FORMAT\n";
        return 0;
    }
    uint32_t V, E;
    if (cin.read((char*)&V, 4).gcount() != 4) return 0;
    if (cin.read((char*)&E, 4).gcount() != 4) return 0;

    vector<vector<uint32_t>> adj(V);
    vector<uint32_t> in_degree(V, 0);

    for (uint32_t i = 0; i < E; ++i) {
        uint32_t u, v;
        if (cin.read((char*)&u, 4).gcount() != 4) return 0;
        if (cin.read((char*)&v, 4).gcount() != 4) return 0;
        if (u < V && v < V) {
            adj[u].push_back(v);
            in_degree[v]++;
        }
    }

    priority_queue<uint32_t, vector<uint32_t>, greater<uint32_t>> pq;
    for (uint32_t i = 0; i < V; ++i) {
        if (in_degree[i] == 0) pq.push(i);
    }

    vector<uint32_t> sorted;
    while (!pq.empty()) {
        uint32_t u = pq.top();
        pq.pop();
        sorted.push_back(u);
        for (uint32_t v : adj[u]) {
            if (--in_degree[v] == 0) {
                pq.push(v);
            }
        }
    }

    if (sorted.size() == V) {
        for (size_t i = 0; i < V; ++i) {
            cout << sorted[i] << (i == V - 1 ? "" : " ");
        }
        cout << "\n";
    } else {
        cout << "CYCLE DETECTED\n";
    }

    return 0;
}
EOF

    g++ -O3 -s /tmp/oracle.cpp -o /app/oracle_graph_parser
    strip /app/oracle_graph_parser
    rm /tmp/oracle.cpp

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/graph_pkg/src
    mkdir -p /home/user/solution

    cat << 'EOF' > /home/user/graph_pkg/src/resolver.cpp
#include <Python.h>

static PyObject* resolve(PyObject* self, PyObject* args) {
    const char* data;
    Py_ssize_t length;
    if (!PyArg_ParseTuple(args, "y#", &data, &length)) {
        return NULL;
    }
    // TODO: implement graph parsing and topological sort
    return PyUnicode_FromString("TODO");
}

static PyMethodDef GraphMethods[] = {
    {"resolve",  resolve, METH_VARARGS, "Resolve graph."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef graphmodule = {
    PyModuleDef_HEAD_INIT,
    "_graph_resolver",
    NULL,
    -1,
    GraphMethods
};

PyMODINIT_FUNC PyInit__graph_resolver(void) {
    return PyModule_Create(&graphmodule);
}
EOF

    cat << 'EOF' > /home/user/graph_pkg/setup.py
from setuptools import setup, Extension

module1 = Extension('_graph_resolver',
                    sources = ['src/resolver.cpp'])

setup (name = 'GraphResolver',
       version = '1.0',
       description = 'This is a demo package',
       ext_modules = [module1]
# Intentional syntax error below
EOF

    chmod -R 777 /home/user
