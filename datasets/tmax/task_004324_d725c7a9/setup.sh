#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make python3.10-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/ext

    cat << 'EOF' > /home/user/app/ext/validator.c
#include <Python.h>

static PyObject* validate_token(PyObject* self, PyObject* args) {
    const char* token;
    if (!PyArg_ParseTuple(args, "s", &token)) {
        return NULL;
    }
    // Simple mock validation
    if (token[0] == 'v' && token[1] == '2') {
        Py_RETURN_TRUE;
    }
    Py_RETURN_FALSE;
}

static PyMethodDef ValidatorMethods[] = {
    {"validate_token", validate_token, METH_VARARGS, "Validate API token."},
    {NULL, NULL, 0, NULL}
};

// Intentionally broken for Python 3 - Python 2 initialization
void initvalidator(void) {
    (void) Py_InitModule("validator", ValidatorMethods);
}
EOF

    cat << 'EOF' > /home/user/app/ext/Makefile
all:
	gcc -shared -o validator.so -fPIC validator.c -I/usr/include/python2.7
EOF

    cat << 'EOF' > /home/user/app/server.py
RATE_LIMIT = 100

from auth import check_request

def handle_request(req):
    if check_request(req):
        return {"status": "ok"}
    return {"status": "error"}
EOF

    cat << 'EOF' > /home/user/app/auth.py
import validator
from server import RATE_LIMIT

def check_request(req):
    # Enforce rate limit logic mock
    if req.get("count", 0) > RATE_LIMIT:
        return False
    return validator.validate_token(req.get("token", ""))
EOF

    cat << 'EOF' > /home/user/app/test_runner.py
import json
import sys

try:
    from server import handle_request

    req = {"token": "v2_secure_token_xyz", "count": 5}
    res = handle_request(req)

    with open("/home/user/migration_result.log", "w") as f:
        f.write(json.dumps(res))
    print("Success")
except Exception as e:
    print(f"Failed: {e}")
    sys.exit(1)
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
