#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential
    pip3 install pytest

    mkdir -p /home/user/waf_pipeline
    cd /home/user/waf_pipeline

    cat << 'EOF' > parser.c
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <string.h>

static PyObject* extract_payload(PyObject* self, PyObject* args) {
    const char* input;
    char buffer[256];

    if (!PyArg_ParseTuple(args, "s", &input)) {
        return NULL;
    }

    // VULNERABILITY: strcpy buffer overflow
    strcpy(buffer, input);

    return Py_BuildValue("s", buffer);
}

static PyMethodDef WafMethods[] = {
    {"extract_payload",  extract_payload, METH_VARARGS, "Extract payload string."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef wafmodule = {
    PyModuleDef_HEAD_INIT,
    "waf_parser",
    NULL,
    -1,
    WafMethods
};

PyMODINIT_FUNC PyInit_waf_parser(void) {
    return PyModule_Create(&wafmodule);
}
EOF

    cat << 'EOF' > requirements.txt
Flask==2.0.1
Werkzeug==1.0.1
EOF

    cat << 'EOF' > rules.json
[
  "admin'--",
  "<script>",
  "DROP TABLE",
  "/etc/passwd"
]
EOF

    cat << 'EOF' > payloads.txt
GET /index.html HTTP/1.1
GET /login?user=admin'-- HTTP/1.1
POST /submit?data=<script>alert(1)</script> HTTP/1.1
GET /assets/style.css HTTP/1.1
GET /api/data?query=SELECT * FROM users; DROP TABLE users; HTTP/1.1
GET /home?file=../../../../etc/passwd HTTP/1.1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
