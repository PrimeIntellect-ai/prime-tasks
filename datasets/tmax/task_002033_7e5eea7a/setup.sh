#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential libssl-dev binutils
    pip3 install pytest

    # Create directories
    mkdir -p /app/vendored/libsectoken-1.2.0/src
    mkdir -p /app/oracle

    # Create broken sectoken.c
    cat << 'EOF' > /app/vendored/libsectoken-1.2.0/src/sectoken.c
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <openssl/sha.h>
#include <cyrpto.h> // Deliberate typo, should be removed or corrected

static PyObject* sign_payload(PyObject* self, PyObject* args) {
    const char* payload;
    if (!PyArg_ParseTuple(args, "s", &payload)) {
        return NULL;
    }

    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256((unsigned char*)payload, strlen(payload), hash);

    return PyBytes_FromStringAndSize((const char*)hash, SHA256_DIGEST_LENGTH);
}

static PyMethodDef SecTokenMethods[] = {
    {"sign_payload", sign_payload, METH_VARARGS, "Generate base cryptographic signature."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef sectokenmodule = {
    PyModuleDef_HEAD_INIT,
    "libsectoken",
    "Legacy security token package.",
    -1,
    SecTokenMethods
};

PyMODINIT_FUNC PyInit_libsectoken(void) {
    return PyModule_Create(&sectokenmodule);
}
EOF

    # Create broken setup.py
    cat << 'EOF' > /app/vendored/libsectoken-1.2.0/setup.py
from setuptools import setup, Extension

module1 = Extension('libsectoken',
                    sources = ['src/sectoken.c']) # Missing libraries=['crypto']

setup (name = 'libsectoken',
       version = '1.2.0',
       description = 'Legacy security token package',
       ext_modules = [module1])
EOF

    # Create oracle C source
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <openssl/sha.h>
#include <openssl/evp.h>

void base64_encode(const unsigned char *input, int length, char *output) {
    EVP_EncodeBlock((unsigned char *)output, input, length);
}

int main(int argc, char **argv) {
    if(argc < 2) {
        fprintf(stderr, "Usage: %s <json_string>\n", argv[0]);
        return 1;
    }

    const char *json = argv[1];
    char payload[4096];
    snprintf(payload, sizeof(payload), "default-src 'none'; script-src 'self';|%s", json);

    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256((unsigned char*)payload, strlen(payload), hash);

    char final_buf[8192];
    int payload_len = strlen(payload);
    memcpy(final_buf, payload, payload_len);
    final_buf[payload_len] = '|';
    memcpy(final_buf + payload_len + 1, hash, SHA256_DIGEST_LENGTH);

    char b64[16384];
    base64_encode((unsigned char*)final_buf, payload_len + 1 + SHA256_DIGEST_LENGTH, b64);

    printf("%s\n", b64);
    return 0;
}
EOF

    # Compile oracle
    gcc -O2 /tmp/oracle.c -o /app/oracle/token_oracle -lcrypto
    strip /app/oracle/token_oracle
    chmod +x /app/oracle/token_oracle
    rm /tmp/oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
