#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev gcc
    pip3 install pytest setuptools

    mkdir -p /home/user/data_processor/data_processor
    mkdir -p /home/user/data_processor/tests
    mkdir -p /home/user/data_processor/scripts

    touch /home/user/data_processor/data_processor/__init__.py

    cat << 'EOF' > /home/user/data_processor/data_processor/config.py
SETTINGS = {"mode": "local"}

def init_ci():
    SETTINGS["mode"] = "ci"
EOF

    cat << 'EOF' > /home/user/data_processor/data_processor/utils.py
from data_processor.config import SETTINGS

MODE = SETTINGS["mode"]

def get_hash(data):
    try:
        from data_processor import fast_hash
        return fast_hash.compute(data)
    except ImportError:
        return "slow_hash_" + data
EOF

    cat << 'EOF' > /home/user/data_processor/data_processor/fast_hash.c
#include <Python.h>

static PyObject* fast_hash_compute(PyObject* self, PyObject* args) {
    const char* input;
    if (!PyArg_ParseTuple(args, "s", &input)) {
        return NULL;
    }
    // simple dummy hash for testing
    return PyUnicode_FromFormat("fast_hash_%s", input);
}

static PyMethodDef FastHashMethods[] = {
    {"compute",  fast_hash_compute, METH_VARARGS, "Compute fast hash."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fashhashmodule = {
    PyModuleDef_HEAD_INIT,
    "fast_hash",
    NULL,
    -1,
    FastHashMethods
};

PyMODINIT_FUNC PyInit_fast_hash(void) {
    return PyModule_Create(&fashhashmodule);
}
EOF

    cat << 'EOF' > /home/user/data_processor/setup.py
from setuptools import setup, Extension
import os

ext_modules = []
if os.environ.get("USE_C_EXT") == "1":
    # BUG: incorrect source path
    ext_modules.append(Extension("data_processor.fast_hash", sources=["src/fast_hash.c"]))

setup(
    name="data_processor",
    version="0.1",
    packages=["data_processor"],
    ext_modules=ext_modules,
)
EOF

    cat << 'EOF' > /home/user/data_processor/tests/test_processing.py
import pytest
from data_processor.config import init_ci
from data_processor.utils import MODE

def test_mode():
    init_ci()
    assert MODE == "ci"

def test_hash():
    from data_processor.utils import get_hash
    assert get_hash("test").startswith("fast_hash_")
EOF

    cat << 'EOF' > /home/user/data_processor/scripts/download_fixtures.sh
#!/bin/bash
# Mock download
echo "dummy data" > fixture.dat
echo "b52b21703eb5eabdd9a1efdd4fbab67215f7b0dc2bbd603e83921946890fbfb1  fixture.dat" > fixture.dat.sha256

# BUG: broken checksum check
if [ "$(cat fixture.dat.sha256)" == "$(sha256sum fixture.dat)" ]; then
    echo "Checksum match"
else
    echo "Checksum mismatch"
    exit 1
fi
EOF

    chmod +x /home/user/data_processor/scripts/download_fixtures.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
