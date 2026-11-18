#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev gcc python3-setuptools
    pip3 install --default-timeout=100 pytest

    mkdir -p /home/user/pipeline/data
    cd /home/user/pipeline

    # 1. Create liblegacy.so
    cat << 'EOF' > legacy.c
int get_multiplier(void) {
    return 73;
}
EOF
    gcc -shared -fPIC -o liblegacy.so legacy.c
    rm legacy.c

    # 2. Create fast_math.c with bugs
    cat << 'EOF' > fast_math.c
#include <Python.h>

static PyObject* calculate_score(PyObject* self, PyObject* args) {
    PyObject* list_obj;
    if (!PyArg_ParseTuple(args, "O", &list_obj)) {
        return NULL;
    }

    Py_ssize_t size = PyList_Size(list_obj);
    long long total_score = 0;

    // BUG 1: Unused variable that causes build failure when -Werror is used
    int unused_var = 42; 

    for (Py_ssize_t i = 0; i < size; i++) {
        PyObject* item = PyList_GetItem(list_obj, i);
        long val = PyLong_AsLong(item);
        // BUG 2: Incorrect formula. Should be val * (i + 1) and multiplied by 73
        total_score += val * i;
    }

    return PyLong_FromLongLong(total_score);
}

static PyMethodDef FastMathMethods[] = {
    {"calculate_score", calculate_score, METH_VARARGS, "Calculate the array score."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fastmathmodule = {
    PyModuleDef_HEAD_INIT,
    "fast_math",
    NULL,
    -1,
    FastMathMethods
};

PyMODINIT_FUNC PyInit_fast_math(void) {
    return PyModule_Create(&fastmathmodule);
}
EOF

    # 3. Create setup.py with -Werror
    cat << 'EOF' > setup.py
from setuptools import setup, Extension

module1 = Extension('fast_math',
                    sources = ['fast_math.c'],
                    extra_compile_args=['-Werror', '-Wunused-variable'])

setup (name = 'FastMath',
       version = '1.0',
       description = 'Fast math operations',
       ext_modules = [module1])
EOF

    # 4. Create query_data.py with a race condition
    cat << 'EOF' > query_data.py
import json
import os
import concurrent.futures
import fast_math

data_dir = '/home/user/pipeline/data'
results = {}

def process_file(filename):
    filepath = os.path.join(data_dir, filename)
    with open(filepath, 'r') as f:
        data = json.load(f)

    score = fast_math.calculate_score(data['values'])

    # RACE CONDITION: read-modify-write on a shared dictionary without locks
    # In CPython, dict updates like this are not atomic.
    current = results.get(filename, 0)
    # Artificial delay to force race condition
    import time; time.sleep(0.001)
    results[filename] = current + score

def main():
    files = [f for f in os.listdir(data_dir) if f.endswith('.json')]

    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
        executor.map(process_file, files)

    with open('/home/user/pipeline/final_results.json', 'w') as f:
        json.dump(results, f, indent=4)

if __name__ == '__main__':
    main()
EOF

    # 5. Generate 500 data files
    cat << 'EOF' > generate_data.py
import json
import os
import random

os.makedirs('/home/user/pipeline/data', exist_ok=True)
random.seed(42)

for i in range(500):
    data = {
        "values": [random.randint(1, 100) for _ in range(50)]
    }
    with open(f'/home/user/pipeline/data/file_{i}.json', 'w') as f:
        json.dump(data, f)
EOF
    python3 generate_data.py
    rm generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
