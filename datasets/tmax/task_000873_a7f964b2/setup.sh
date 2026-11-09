#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git build-essential sqlite3 libsqlite3-dev
    pip3 install pytest setuptools

    useradd -m -s /bin/bash user || true

    # Create DB
    cat << 'EOF' > /tmp/make_db.py
import sqlite3
import random
random.seed(42)
conn = sqlite3.connect('/home/user/sensor_data.db')
c = conn.cursor()
c.execute('CREATE TABLE sensor_data (value REAL)')
mean = 1e8
for _ in range(1000):
    val = mean + random.gauss(0, 0.1)
    c.execute('INSERT INTO sensor_data VALUES (?)', (val,))
conn.commit()
conn.close()
EOF
    python3 /tmp/make_db.py

    # Create oracle
    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <sqlite3.h>

int main() {
    sqlite3 *db;
    sqlite3_stmt *stmt;
    if (sqlite3_open("/home/user/sensor_data.db", &db) != SQLITE_OK) return 1;
    if (sqlite3_prepare_v2(db, "SELECT value FROM sensor_data", -1, &stmt, NULL) != SQLITE_OK) return 1;

    double count = 0, mean = 0, M2 = 0;
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        double val = sqlite3_column_double(stmt, 0);
        count += 1;
        double delta = val - mean;
        mean += delta / count;
        double delta2 = val - mean;
        M2 += delta * delta2;
    }
    sqlite3_finalize(stmt);
    sqlite3_close(db);

    double variance = M2 / (count - 1);
    printf("%.10f\n", variance);
    return 0;
}
EOF
    gcc -O3 /tmp/oracle.c -o /app/oracle_bin -lsqlite3 -lm
    strip /app/oracle_bin

    # Create git repo
    mkdir -p /home/user/pipeline_repo/c_src
    cd /home/user/pipeline_repo
    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    cat << 'EOF' > process_data.py
import sqlite3
import _fast_agg

conn = sqlite3.connect('/home/user/sensor_data.db')
c = conn.cursor()
c.execute('SELECT value FROM sensor_data')
data = [row[0] for row in c.fetchall()]
conn.close()

print(f"{_fast_agg.variance(data):.10f}")
EOF

    cat << 'EOF' > setup.py
from setuptools import setup, Extension
module1 = Extension('_fast_agg', sources = ['c_src/agg.c'], extra_link_args=['-lm'])
setup(name='FastAgg', version='1.0', ext_modules=[module1])
EOF

    cat << 'EOF' > c_src/agg.c
#include <Python.h>
#include <math.h>

static PyObject* variance(PyObject* self, PyObject* args) {
    PyObject* listObj;
    if (!PyArg_ParseTuple(args, "O!", &PyList_Type, &listObj)) return NULL;
    Py_ssize_t count = PyList_Size(listObj);
    double mean = 0, M2 = 0;
    for (Py_ssize_t i = 0; i < count; i++) {
        PyObject* floatObj = PyList_GetItem(listObj, i);
        double val = PyFloat_AsDouble(floatObj);
        double delta = val - mean;
        mean += delta / (i + 1);
        M2 += delta * (val - mean);
    }
    double var = M2 / (count - 1);
    return PyFloat_FromDouble(var);
}

static PyMethodDef FastAggMethods[] = {
    {"variance",  variance, METH_VARARGS, "Calculate variance."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fastaggmodule = {
    PyModuleDef_HEAD_INIT, "_fast_agg", NULL, -1, FastAggMethods
};

PyMODINIT_FUNC PyInit__fast_agg(void) {
    return PyModule_Create(&fastaggmodule);
}
EOF

    git add .
    git commit -m "Initial commit"

    for i in $(seq 1 200); do
        echo "# dummy $i" >> dummy.txt
        git add dummy.txt

        if [ "$i" -eq 100 ]; then
            sed -i "s/extra_link_args=\['-lm'\]/extra_link_args=\[\]/" setup.py
            git add setup.py
        elif [ "$i" -eq 120 ]; then
            sed -i "s/extra_link_args=\[\]/extra_link_args=\['-lm'\]/" setup.py
            git add setup.py
        elif [ "$i" -eq 150 ]; then
            cat << 'EOF' > c_src/agg.c
#include <Python.h>
#include <math.h>

static PyObject* variance(PyObject* self, PyObject* args) {
    PyObject* listObj;
    if (!PyArg_ParseTuple(args, "O!", &PyList_Type, &listObj)) return NULL;
    Py_ssize_t count = PyList_Size(listObj);
    double sum = 0, sum_sq = 0;
    for (Py_ssize_t i = 0; i < count; i++) {
        PyObject* floatObj = PyList_GetItem(listObj, i);
        double val = PyFloat_AsDouble(floatObj);
        sum += val;
        sum_sq += val * val;
    }
    double mean = sum / count;
    double var = (sum_sq / count) - (mean * mean);
    var = var * count / (count - 1); // sample variance
    return PyFloat_FromDouble(var);
}

static PyMethodDef FastAggMethods[] = {
    {"variance",  variance, METH_VARARGS, "Calculate variance."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fastaggmodule = {
    PyModuleDef_HEAD_INIT, "_fast_agg", NULL, -1, FastAggMethods
};

PyMODINIT_FUNC PyInit__fast_agg(void) {
    return PyModule_Create(&fastaggmodule);
}
EOF
            git add c_src/agg.c
        fi

        git commit -m "Commit $i"
    done

    python3 setup.py build_ext --inplace

    chmod -R 777 /home/user
