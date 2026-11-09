#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential nginx curl
pip3 install pytest

mkdir -p /home/user/workspace/log-merger
mkdir -p /home/user/workspace/logs
mkdir -p /home/user/workspace/output
mkdir -p /home/user/workspace/nginx_temp/logs

cat << 'EOF' > /home/user/workspace/log-merger/reference.py
def fast_hash(s: str) -> int:
    return sum(ord(c) for c in s) % 256
EOF

cat << 'EOF' > /home/user/workspace/log-merger/fast_hash.c
#define PY_SSIZE_T_CLEAN
#include <Python.h>

static PyObject* fast_hash(PyObject* self, PyObject* args) {
    const char* s;
    if (!PyArg_ParseTuple(args, "s", &s)) {
        return NULL;
    }

    long hash_val = 0;
    // TODO: implement the logic from reference.py here
    // Hint: iterate over the string 's' until '\0', sum characters, modulo 256.

    return PyLong_FromLong(hash_val);
}

static PyMethodDef FastHashMethods[] = {
    {"fast_hash",  fast_hash, METH_VARARGS, "Calculate fast hash."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fasthashmodule = {
    PyModuleDef_HEAD_INIT,
    "fast_hash",
    NULL,
    -1,
    FastHashMethods
};

PyMODINIT_FUNC PyInit_fast_hash(void) {
    return PyModule_Create(&fasthashmodule);
}
EOF

cat << 'EOF' > /home/user/workspace/log-merger/setup.py
from setuptools import setup, Extension

# TODO: Fix the Extension definition to compile fast_hash.c
module1 = Extension('MISSING_MODULE_NAME',
                    sources = ['MISSING_FILE.c'])

setup (name = 'log_merger',
       version = '1.0',
       description = 'Log merging package',
       ext_modules = [module1],
       py_modules = ['log_merger'])
EOF

cat << 'EOF' > /home/user/workspace/log-merger/log_merger.py
import sys
import fast_hash

def process_logs(files):
    lines = []
    for fpath in files:
        with open(fpath, 'r') as f:
            lines.extend(f.readlines())

    # Sort by timestamp (assuming first word is timestamp)
    lines.sort(key=lambda x: x.split()[0])

    for line in lines:
        line = line.strip()
        h = fast_hash.fast_hash(line)
        print(f"[{h:03d}] {line}")

if __name__ == "__main__":
    process_logs(sys.argv[1:])
EOF

cat << 'EOF' > /home/user/workspace/logs/serverA.log
2023-10-01T10:00:02 INFO App started
2023-10-01T10:00:05 WARN High memory
EOF

cat << 'EOF' > /home/user/workspace/logs/serverB.log
2023-10-01T10:00:01 INFO DB connected
2023-10-01T10:00:04 ERROR Connection lost
EOF

cat << 'EOF' > /home/user/workspace/logs/baseline.log
[105] 2023-10-01T10:00:01 INFO DB connected
[114] 2023-10-01T10:00:02 INFO App started
[152] 2023-10-01T10:00:04 ERROR Connection lost
[065] 2023-10-01T10:00:05 INFO Normal memory
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
