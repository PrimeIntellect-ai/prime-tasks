#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install pytest numpy

    # Create user
    useradd -m -s /bin/bash user || true

    # Create vendored package directory
    mkdir -p /app/fastvec-1.0

    # Write setup.py
    cat << 'EOF' > /app/fastvec-1.0/setup.py
from setuptools import setup, Extension
import numpy as np

ext = Extension(
    'fastvec',
    sources=['fastvec.c'],
    include_dirs=[np.get_include()],
    extra_compile_args=['-O0', '-g']
)

setup(
    name='fastvec',
    version='1.0',
    ext_modules=[ext]
)
EOF

    # Write fastvec.c
    cat << 'EOF' > /app/fastvec-1.0/fastvec.c
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <numpy/arrayobject.h>

typedef struct {
    PyObject_HEAD
    PyArrayObject *refs;
} IndexObject;

static void Index_dealloc(IndexObject *self) {
    Py_XDECREF(self->refs);
    Py_TYPE(self)->tp_free((PyObject *) self);
}

static int Index_init(IndexObject *self, PyObject *args, PyObject *kwds) {
    PyObject *refs_obj = NULL;
    if (!PyArg_ParseTuple(args, "O", &refs_obj)) return -1;
    self->refs = (PyArrayObject *)PyArray_FROM_OTF(refs_obj, NPY_DOUBLE, NPY_ARRAY_IN_ARRAY);
    if (!self->refs) return -1;
    return 0;
}

static PyObject *Index_query(IndexObject *self, PyObject *args, PyObject *kwds) {
    PyObject *queries_obj = NULL;
    int k = 5;
    static char *kwlist[] = {"queries", "k", NULL};
    if (!PyArg_ParseTupleAndKeywords(args, kwds, "O|i", kwlist, &queries_obj, &k)) return NULL;

    PyArrayObject *queries = (PyArrayObject *)PyArray_FROM_OTF(queries_obj, NPY_DOUBLE, NPY_ARRAY_IN_ARRAY);
    if (!queries) return NULL;

    npy_intp num_queries = PyArray_DIM(queries, 0);
    npy_intp dim = PyArray_DIM(queries, 1);
    npy_intp num_refs = PyArray_DIM(self->refs, 0);

    double *q_data = (double *)PyArray_DATA(queries);
    double *r_data = (double *)PyArray_DATA(self->refs);

    npy_intp dims[2] = {num_queries, k};
    PyArrayObject *result = (PyArrayObject *)PyArray_SimpleNew(2, dims, NPY_INT64);
    int64_t *res_data = (int64_t *)PyArray_DATA(result);

    for (npy_intp i = 0; i < num_queries; i++) {
        double *q = q_data + i * dim;
        double *best_dists = (double *)malloc(k * sizeof(double));
        int64_t *best_idx = (int64_t *)malloc(k * sizeof(int64_t));
        for (int j=0; j<k; j++) best_dists[j] = 1e30;

        for (npy_intp j = 0; j < num_refs; j++) {
            double *r = r_data + j * dim;
            double dist = 0;
            for (npy_intp d = 0; d < dim; d++) {
                double diff = q[d] - r[d];
                dist += diff * diff;
            }
            if (dist < best_dists[k-1]) {
                int pos = k - 1;
                while (pos > 0 && dist < best_dists[pos-1]) {
                    best_dists[pos] = best_dists[pos-1];
                    best_idx[pos] = best_idx[pos-1];
                    pos--;
                }
                best_dists[pos] = dist;
                best_idx[pos] = j;
            }
        }
        for (int j=0; j<k; j++) {
            res_data[i * k + j] = best_idx[j];
        }
        free(best_dists);
        free(best_idx);
    }

    Py_DECREF(queries);
    return (PyObject *)result;
}

static PyMethodDef Index_methods[] = {
    {"query", (PyCFunction)Index_query, METH_VARARGS | METH_KEYWORDS, "Query nearest neighbors"},
    {NULL}
};

static PyTypeObject IndexType = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "fastvec.Index",
    .tp_doc = "Index objects",
    .tp_basicsize = sizeof(IndexObject),
    .tp_itemsize = 0,
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_new = PyType_GenericNew,
    .tp_init = (initproc) Index_init,
    .tp_dealloc = (destructor) Index_dealloc,
    .tp_methods = Index_methods,
};

static PyModuleDef fastvecmodule = {
    PyModuleDef_HEAD_INIT,
    .m_name = "fastvec",
    .m_doc = "Fast vector search",
    .m_size = -1,
};

PyMODINIT_FUNC PyInit_fastvec(void) {
    PyObject *m;
    import_array();
    if (PyType_Ready(&IndexType) < 0) return NULL;
    m = PyModule_Create(&fastvecmodule);
    if (m == NULL) return NULL;
    Py_INCREF(&IndexType);
    if (PyModule_AddObject(m, "Index", (PyObject *) &IndexType) < 0) {
        Py_DECREF(&IndexType);
        Py_DECREF(m);
        return NULL;
    }
    return m;
}
EOF

    # Generate data chunks
    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import os

os.makedirs('/home/user/data', exist_ok=True)
np.random.seed(42)

for i in range(10):
    ref_chunk = np.random.randn(10000, 512).astype(np.float64)
    np.save(f'/home/user/data/ref_chunk_{i}.npy', ref_chunk)

queries = np.random.randn(1000, 512).astype(np.float64)
np.save('/home/user/data/queries.npy', queries)

pca = np.random.randn(128, 512).astype(np.float64)
np.save('/home/user/data/pca_matrix.npy', pca)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    # Set permissions
    chmod -R 777 /app
    chmod -R 777 /home/user
