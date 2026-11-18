#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev gcc binutils
    pip3 install pytest setuptools

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy_app
    cd /home/user/legacy_app

    # 1. Create the dummy log
    cat << 'EOF' > crash.log
[INFO] Worker starting
[INFO] Processing standard payloads
[ERROR] Worker crashed unexpectedly!
[FATAL] Segmentation fault on anomalous payload: 0xcafebabe0042
[INFO] Exiting...
EOF

    # 2. Create the static library source and compile it
    cat << 'EOF' > magic.c
#include <string.h>

char* process_payload_v2_fast(const char* payload, int len) {
    if (len == 6 && 
        (unsigned char)payload[0] == 0xca && 
        (unsigned char)payload[1] == 0xfe && 
        (unsigned char)payload[2] == 0xba && 
        (unsigned char)payload[3] == 0xbe && 
        (unsigned char)payload[4] == 0x00 && 
        (unsigned char)payload[5] == 0x42) {
        return "SUCCESS_DECODED_ANOMALY_99X";
    }
    return "INVALID_PAYLOAD";
}
EOF

    gcc -c magic.c -o magic.o
    ar rcs libmagic.a magic.o
    rm magic.c magic.o

    # 3. Create the broken C extension
    cat << 'EOF' > processor.c
#define PY_SSIZE_T_CLEAN
#include <Python.h>

// Wrong function declaration!
extern char* process_payload(const char* payload, int len);

static PyObject* processor_run(PyObject* self, PyObject* args) {
    const char* payload;
    Py_ssize_t len;

    if (!PyArg_ParseTuple(args, "y#", &payload, &len)) {
        return NULL;
    }

    // Calling the wrong function!
    char* result = process_payload(payload, (int)len);

    return PyUnicode_FromString(result);
}

static PyMethodDef ProcessorMethods[] = {
    {"run",  processor_run, METH_VARARGS, "Run the payload processor."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef processormodule = {
    PyModuleDef_HEAD_INIT,
    "processor",
    NULL,
    -1,
    ProcessorMethods
};

PyMODINIT_FUNC PyInit_processor(void) {
    return PyModule_Create(&processormodule);
}
EOF

    # 4. Create the broken setup.py
    cat << 'EOF' > setup.py
from setuptools import setup, Extension

module1 = Extension('processor',
                    sources = ['processor.c'])

setup (name = 'Processor',
       version = '1.0',
       description = 'Legacy processing module',
       ext_modules = [module1])
EOF

    chown -R user:user /home/user/legacy_app
    chmod -R 777 /home/user
