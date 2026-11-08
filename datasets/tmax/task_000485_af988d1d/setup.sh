#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential

    pip3 install --no-cache-dir pytest numpy scipy networkx papermill jupyter nbformat ipykernel

    # Create vendored library
    mkdir -p /app/graph_factor_lib/graph_factor_lib

    cat << 'EOF' > /app/graph_factor_lib/setup.py
from setuptools import setup, Extension, find_packages

ext_modules = [
    Extension(
        'graph_factor_lib._factorize',
        sources=['graph_factor_lib/_factorize.c'],
        # Missing include_dirs=[np.get_include()]
    )
]

setup(
    name='graph_factor_lib',
    version='0.1.0',
    packages=find_packages(),
    ext_modules=ext_modules,
)
EOF

    cat << 'EOF' > /app/graph_factor_lib/graph_factor_lib/_factorize.c
#include <Python.h>
#include <numpy/arrayobject.h>

static PyObject* dummy(PyObject* self, PyObject* args) {
    Py_RETURN_NONE;
}

static PyMethodDef FactorizeMethods[] = {
    {"dummy", dummy, METH_VARARGS, "Dummy function."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef factorizemodule = {
    PyModuleDef_HEAD_INIT,
    "_factorize",
    NULL,
    -1,
    FactorizeMethods
};

PyMODINIT_FUNC PyInit__factorize(void) {
    import_array();
    return PyModule_Create(&factorizemodule);
}
EOF

    cat << 'EOF' > /app/graph_factor_lib/graph_factor_lib/solver.py
import numpy as np

def solve_laplacian(L):
    inv_L = np.linalg.inv(L)
    return inv_L

def factorize(adjacency):
    degree = np.diag(np.sum(adjacency, axis=1))
    L = degree - adjacency
    return solve_laplacian(L)
EOF

    cat << 'EOF' > /app/graph_factor_lib/graph_factor_lib/__init__.py
from .solver import factorize
EOF

    # Create user and directories
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data
    mkdir -p /home/user/notebooks_out

    # Create data files
    cat << 'EOF' > /home/user/data/mol_1.edges
0 1
1 2
2 3
3 0
EOF

    cat << 'EOF' > /home/user/data/mol_2.edges
0 1
1 2
2 0
EOF

    # Create evaluate_model.ipynb
    cat << 'EOF' > /home/user/evaluate_model.ipynb
{
 "cells": [
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {
    "tags": ["parameters"]
   },
   "outputs": [],
   "source": [
    "input_graph = '/home/user/data/mol_1.edges'"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "import os\n",
    "import networkx as nx\n",
    "import numpy as np\n",
    "import graph_factor_lib\n",
    "\n",
    "G = nx.read_edgelist(input_graph, nodetype=int)\n",
    "n = max(G.nodes()) + 1\n",
    "adj = nx.to_numpy_array(G, nodelist=range(n))\n",
    "\n",
    "try:\n",
    "    res = graph_factor_lib.factorize(adj)\n",
    "    kl = 0.04\n",
    "except Exception as e:\n",
    "    kl = 1.0\n",
    "\n",
    "basename = os.path.splitext(os.path.basename(input_graph))[0]\n",
    "with open(f'/home/user/{basename}_metrics.txt', 'w') as f:\n",
    "    f.write(str(kl))\n"
   ]
  }
 ],
 "metadata": {
  "kernelspec": {
   "display_name": "Python 3",
   "language": "python",
   "name": "python3"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 4
}
EOF

    chmod -R 777 /app/graph_factor_lib
    chmod -R 777 /home/user
