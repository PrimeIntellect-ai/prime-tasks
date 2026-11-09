#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev gcc make
    pip3 install pytest setuptools

    mkdir -p /home/user/workspace/c_src
    mkdir -p /home/user/workspace/python_pkg
    mkdir -p /home/user/workspace/tests

    # c_src/htmlparser.h
    cat << 'EOF' > /home/user/workspace/c_src/htmlparser.h
#ifndef HTMLPARSER_H
#define HTMLPARSER_H
char* sanitize(const char* input);
#endif
EOF

    # c_src/htmlparser.c
    cat << 'EOF' > /home/user/workspace/c_src/htmlparser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "htmlparser.h"

char* sanitize(const char* input) {
    char* output = malloc(strlen(input) + 1);
    strcpy(output, input);
    // VULNERABLE: Does nothing.
    return output;
}
EOF

    # c_src/security_fix.patch
    cat << 'EOF' > /home/user/workspace/c_src/security_fix.patch
--- htmlparser.c
+++ htmlparser.c
@@ -7,6 +7,16 @@
 char* sanitize(const char* input) {
     char* output = malloc(strlen(input) + 1);
     strcpy(output, input);
-    // VULNERABLE: Does nothing.
+    
+    // Very basic/naive strip for testing purposes
+    char *match;
+    while ((match = strstr(output, "eval("))) {
+        strncpy(match, "SAFE_", 5);
+    }
+    while ((match = strstr(output, "onerror"))) {
+        strncpy(match, "onsafe ", 7);
+    }
+    
     return output;
 }
EOF

    # c_src/Makefile
    cat << 'EOF' > /home/user/workspace/c_src/Makefile
all:
	gcc -shared -o libhtmlparser.so -fPIC htmlparser.c
clean:
	rm -f *.so
EOF

    # python_pkg/fast_sanitizer.c
    cat << 'EOF' > /home/user/workspace/python_pkg/fast_sanitizer.c
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include "htmlparser.h"

static PyObject* method_sanitize(PyObject* self, PyObject* args) {
    const char* input;
    if (!PyArg_ParseTuple(args, "s", &input)) {
        return NULL;
    }
    char* sanitized_str = sanitize(input);
    PyObject* result = PyUnicode_FromString(sanitized_str);
    free(sanitized_str);
    return result;
}

static PyMethodDef FastSanitizerMethods[] = {
    {"sanitize", method_sanitize, METH_VARARGS, "Sanitize HTML string."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef fastsanitizermodule = {
    PyModuleDef_HEAD_INIT,
    "fast_sanitizer",
    "Fast XSS Sanitization.",
    -1,
    FastSanitizerMethods
};

PyMODINIT_FUNC PyInit_fast_sanitizer(void) {
    return PyModule_Create(&fastsanitizermodule);
}
EOF

    # python_pkg/setup.py
    cat << 'EOF' > /home/user/workspace/python_pkg/setup.py
from setuptools import setup, Extension

s_ext = Extension(
    'fast_sanitizer',
    sources=['fast_sanitizer.c'],
    libraries=['htmlparser'],
    # Missing include and lib dirs
)

setup(
    name='fast_sanitizer',
    version='1.0',
    ext_modules=[s_ext]
)
EOF

    # tests/payloads.js
    cat << 'EOF' > /home/user/workspace/tests/payloads.js
function get_payloads() {
    return [
        { id: 1, payload: "<script>alert(1)</script>" },
        { id: 2, payload: "<img src=x onerror=alert(1)>" },
        { id: 3, payload: "javascript:eval('alert(1)')" }
    ];
}
module.exports = { get_payloads };
EOF

    # tests/test_runner.py
    cat << 'EOF' > /home/user/workspace/tests/test_runner.py
import sys
import xml.etree.ElementTree as ET

try:
    import fast_sanitizer
    import payloads
except ImportError as e:
    print(f"Failed to import: {e}")
    sys.exit(1)

def run_tests():
    data = payloads.get_payloads()

    root = ET.Element("TestResults")
    for item in data:
        result_elem = ET.SubElement(root, "Result")
        ET.SubElement(result_elem, "ID").text = str(item["id"])
        ET.SubElement(result_elem, "Original").text = item["payload"]
        sanitized = fast_sanitizer.sanitize(item["payload"])
        ET.SubElement(result_elem, "Sanitized").text = sanitized

    tree = ET.ElementTree(root)
    tree.write("/home/user/workspace/tests/results.xml")

if __name__ == "__main__":
    run_tests()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
