#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install pytest packaging

    mkdir -p /home/user/sec_artifact/sec_artifact

    cat << 'EOF' > /home/user/sec_artifact/setup.py
import sys
from setuptools import setup, find_packages

# BUG: Naive string comparison breaks on 3.10
if sys.version.split()[0] < "3.8":
    print("Error: Python >= 3.8 required.")
    sys.exit(1)

setup(
    name="sec_artifact",
    version="1.0.0",
    packages=find_packages(),
    entry_points={
        'console_scripts': [
            'sec_artifact=sec_artifact.cli:main',
        ],
    },
    install_requires=["packaging"],
)
EOF

    cat << 'EOF' > /home/user/sec_artifact/sec_artifact/verifier.c
#include <Python.h>
#include <string.h>

static PyObject* verify_hash(PyObject* self, PyObject* args) {
    const char* hash;
    if (!PyArg_ParseTuple(args, "s", &hash)) {
        return NULL;
    }
    // Dummy check: assume valid if length >= 8
    int is_valid = strlen(hash) >= 8 ? 1 : 0;
    return Py_BuildValue("i", is_valid);
}

static PyMethodDef VerifierMethods[] = {
    {"verify_hash", verify_hash, METH_VARARGS, "Verify a hash."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef verifiermodule = {
    PyModuleDef_HEAD_INIT,
    "verifier",
    NULL,
    -1,
    VerifierMethods
};

PyMODINIT_FUNC PyInit_verifier(void) {
    return PyModule_Create(&verifiermodule);
}
EOF

    cat << 'EOF' > /home/user/sec_artifact/sec_artifact/__init__.py
EOF

    cat << 'EOF' > /home/user/sec_artifact/sec_artifact/cli.py
import json
import sys
try:
    from sec_artifact.verifier import verify_hash
except ImportError:
    print("CRITICAL ERROR: C-Extension 'verifier' not found. Build failed.")
    sys.exit(1)

def main():
    if len(sys.argv) < 2:
        print("Usage: sec_artifact check <file>")
        sys.exit(1)

    with open(sys.argv[1], 'r') as f:
        data = json.load(f)

    if data.get("schema_version") != "2.0":
        print("Invalid schema version.")
        sys.exit(1)

    for item in data.get("artifacts", []):
        valid = verify_hash(item["hash_value"])
        status = "VALID" if valid else "INVALID"
        print(f"Artifact {item['identifier']} ({item['hash_type']}): {status}")

if __name__ == '__main__':
    main()
EOF

    cat << 'EOF' > /home/user/artifacts_v1.json
{
    "version": "1.0",
    "items": [
        {"id": "web-frontend-bundle", "checksum": "a1b2c3d4e5f6", "type": "sha256"},
        {"id": "auth-service-bin", "checksum": "abc", "type": "md5"},
        {"id": "database-schema-sql", "checksum": "1234567890abcdef", "type": "sha1"}
    ]
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
