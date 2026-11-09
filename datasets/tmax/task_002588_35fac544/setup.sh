#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential curl
    pip3 install pytest setuptools

    mkdir -p /home/user/math_pr
    cat << 'EOF' > /home/user/math_pr/server.py
import http.server
import socketserver
import urllib.parse
import mathstack

class MathServer(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/eval/"):
            # BUG: Missing urllib.parse.unquote
            expr = self.path.split("/eval/")[1]
            try:
                result = mathstack.eval(expr)
                self.send_response(200)
                self.send_header("Content-type", "text/plain")
                self.end_headers()
                self.wfile.write(str(result).encode())
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(str(e).encode())
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == "__main__":
    with socketserver.TCPServer(("", 8080), MathServer) as httpd:
        httpd.serve_forever()
EOF

    cat << 'EOF' > /home/user/math_pr/mathstack.c
#include <Python.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

static PyObject* mathstack_eval(PyObject* self, PyObject* args) {
    const char* expr;
    if (!PyArg_ParseTuple(args, "s", &expr)) {
        return NULL;
    }

    // BUG: Stack size is only 5.
    int stack[5];
    int top = 0;

    char* expr_copy = strdup(expr);
    char* token = strtok(expr_copy, " ");

    while (token != NULL) {
        if (strcmp(token, "ADD") == 0) {
            if (top < 2) goto error;
            int b = stack[--top];
            int a = stack[--top];
            stack[top++] = a + b;
        } else if (strcmp(token, "SUB") == 0) {
            if (top < 2) goto error;
            int b = stack[--top];
            int a = stack[--top];
            stack[top++] = a - b;
        } else if (strcmp(token, "MUL") == 0) {
            if (top < 2) goto error;
            int b = stack[--top];
            int a = stack[--top];
            stack[top++] = a * b;
        } else if (strcmp(token, "DIV") == 0) {
            if (top < 2) goto error;
            int b = stack[--top];
            int a = stack[--top];
            if (b == 0) goto error;
            // BUG: Integer division instead of floor division
            stack[top++] = a / b;
        } else {
            stack[top++] = atoi(token);
        }
        token = strtok(NULL, " ");
    }

    int result = stack[0];
    free(expr_copy);
    return PyLong_FromLong(result);

error:
    free(expr_copy);
    PyErr_SetString(PyExc_RuntimeError, "Evaluation error");
    return NULL;
}

static PyMethodDef MathStackMethods[] = {
    {"eval",  mathstack_eval, METH_VARARGS, "Evaluate RPN."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef mathstackmodule = {
    PyModuleDef_HEAD_INIT,
    "mathstack",
    NULL,
    -1,
    MathStackMethods
};

PyMODINIT_FUNC PyInit_mathstack(void) {
    return PyModule_Create(&mathstackmodule);
}
EOF

    cat << 'EOF' > /home/user/math_pr/setup.py
from setuptools import setup, Extension
module1 = Extension('mathstack', sources = ['mathstack.c'])
setup(name = 'MathStack', version = '1.0', description = 'Math Evaluator', ext_modules = [module1])
EOF

    chmod +x /home/user/math_pr/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
