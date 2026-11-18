#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev gcc zlib1g-dev
    pip3 install pytest

    # Create vendored package directory
    mkdir -p /app/vendored/fast_forensic_hash

    # Create hash_module.c
    cat << 'EOF' > /app/vendored/fast_forensic_hash/hash_module.c
#include <Python.h>
#include <zlib.h>

static PyObject* compute_hash(PyObject* self, PyObject* args) {
    const char* data;
    Py_ssize_t length;

    if (!PyArg_ParseTuple(args, "y#", &data, &length)) {
        return NULL;
    }

    unsigned long c = crc32(0L, Z_NULL, 0);
    c = crc32(c, (const Bytef*)data, length);

    unsigned long a = adler32(0L, Z_NULL, 0);
    a = adler32(a, (const Bytef*)data, length);

    unsigned char hash_bytes[8];
    hash_bytes[0] = (c >> 24) & 0xFF;
    hash_bytes[1] = (c >> 16) & 0xFF;
    hash_bytes[2] = (c >> 8) & 0xFF;
    hash_bytes[3] = c & 0xFF;
    hash_bytes[4] = (a >> 24) & 0xFF;
    hash_bytes[5] = (a >> 16) & 0xFF;
    hash_bytes[6] = (a >> 8) & 0xFF;
    hash_bytes[7] = a & 0xFF;

    return PyBytes_FromStringAndSize((const char*)hash_bytes, 8);
}

static PyMethodDef HashMethods[] = {
    {"compute_hash", compute_hash, METH_VARARGS, "Compute forensic hash."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef hashmodule = {
    PyModuleDef_HEAD_INIT,
    "fast_forensic_hash",
    NULL,
    -1,
    HashMethods
};

PyMODINIT_FUNC PyInit_fast_forensic_hash(void) {
    return PyModule_Create(&hashmodule);
}
EOF

    # Create setup.py with perturbation (zlib instead of z)
    cat << 'EOF' > /app/vendored/fast_forensic_hash/setup.py
from setuptools import setup, Extension

module1 = Extension('fast_forensic_hash',
                    sources = ['hash_module.c'],
                    libraries = ['zlib'])

setup(name = 'fast_forensic_hash',
      version = '1.0.0',
      description = 'Fast forensic hash',
      ext_modules = [module1])
EOF

    # Create oracle
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/analyze_oracle
#!/usr/bin/env python3
import sys
import base64
import zlib

def main():
    if len(sys.argv) != 2:
        sys.exit(1)
    b64_str = sys.argv[1]
    try:
        data = base64.b64decode(b64_str, validate=True)
    except Exception:
        print("INVALID_INPUT")
        sys.exit(1)

    c = zlib.crc32(data) & 0xFFFFFFFF
    a = zlib.adler32(data) & 0xFFFFFFFF

    h = (c << 32) | a
    print(f"{h:016x}")

if __name__ == "__main__":
    main()
EOF
    chmod +x /opt/oracle/analyze_oracle

    # Set permissions
    chmod -R 777 /app
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
