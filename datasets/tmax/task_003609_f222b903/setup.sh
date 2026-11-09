#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev python3-setuptools build-essential
    pip3 install pytest

    mkdir -p /home/user/project

    cat << 'EOF' > /home/user/project/graph.json
{
  "A": {"deps": [], "val": "gnirts_trohs"},
  "B": {"deps": ["A"], "val": "sgnirts_regnol_emosemos"},
  "C": {"deps": ["A"], "val": "tset_a_si_siht"},
  "D": {"deps": ["B", "C"], "val": "dlrow_olleh"}
}
EOF

    cat << 'EOF' > /home/user/project/setup.py
from setuptools import setup, Extension

module1 = Extension('myext', sources = ['myext.c'])

setup(name = 'myext',
      version = '1.0',
      description = 'String reversal extension',
      ext_modules = [module1])
EOF

    cat << 'EOF' > /home/user/project/myext.c
#define PY_SSIZE_T_CLEAN
#include <Python.h>

static PyObject* reverse_string(PyObject* self, PyObject* args) {
    const char* input;
    Py_ssize_t len;

    if (!PyArg_ParseTuple(args, "s#", &input, &len)) {
        return NULL;
    }

    // BUG: Missing +1 for null terminator, causes heap buffer overflow
    char* reversed = (char*)malloc(len);
    if (!reversed) return PyErr_NoMemory();

    for (Py_ssize_t i = 0; i < len; i++) {
        reversed[i] = input[len - 1 - i];
    }
    reversed[len] = '\0'; // BUG: Out-of-bounds write

    PyObject* result = Py_BuildValue("s", reversed);
    free(reversed);
    return result;
}

static PyMethodDef MyExtMethods[] = {
    {"reverse_string", reverse_string, METH_VARARGS, "Reverses a string."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef myextmodule = {
    PyModuleDef_HEAD_INIT,
    "myext",
    NULL,
    -1,
    MyExtMethods
};

PyMODINIT_FUNC PyInit_myext(void) {
    return PyModule_Create(&myextmodule);
}
EOF

    cat << 'EOF' > /home/user/project/process.py
import json
import myext

def topological_sort(graph):
    # BUG: broken implementation
    visited = set()
    order = []

    def dfs(node):
        if node not in visited:
            visited.add(node)
            for dep in graph[node]['deps']:
                dfs(dep)
            order.append(node)

    # Python 2ism: iteritems
    for node, data in graph.iteritems():
        dfs(node)

    return order

def main():
    with open('graph.json', 'r') as f:
        graph = json.load(f)

    order = topological_sort(graph)

    results = []
    for node in order:
        val = graph[node]['val']
        # Use C extension
        reversed_val = myext.reverse_string(val)
        results.append(reversed_val)

    results.sort()

    with open('/home/user/output.txt', 'w') as f:
        for res in results:
            f.write(res + '\n')

    # Python 2ism: print
    print "Processing complete."

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
