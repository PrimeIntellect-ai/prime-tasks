#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev golang-go
    pip3 install pytest setuptools

    mkdir -p /home/user/project
    cd /home/user/project

    cat << 'EOF' > setup.py
from setuptools import setup, Extension
import sys

print "Starting build..."

semver_module = Extension('semver_ext', sources = ['semver_ext.c'])

setup(name = 'semver_ext',
      version = '1.0',
      description = 'Semantic version parser and comparer',
      ext_modules = [semver_module])
EOF

    cat << 'EOF' > semver_ext.c
#include <Python.h>
#include <string.h>
#include <stdlib.h>

// Extremely basic semver check: assume X.Y.Z
// Returns 1 if v1 >= v2, else 0
int compare_versions(const char* v1, const char* v2) {
    int m1=0, mi1=0, p1=0;
    int m2=0, mi2=0, p2=0;
    sscanf(v1, "%d.%d.%d", &m1, &mi1, &p1);
    sscanf(v2, "%d.%d.%d", &m2, &mi2, &p2);

    if (m1 != m2) return m1 > m2 ? 1 : 0;
    if (mi1 != mi2) return mi1 > mi2 ? 1 : 0;
    return p1 >= p2 ? 1 : 0;
}

static PyObject* parse_and_compare(PyObject* self, PyObject* args) {
    const char* url_path;
    const char* target;

    if (!PyArg_ParseTuple(args, "ss", &url_path, &target)) {
        return NULL;
    }

    // Extract version from end of URL (e.g., /api/pkg/1.2.3 -> 1.2.3)
    const char* last_slash = strrchr(url_path, '/');
    if (!last_slash) last_slash = url_path - 1;
    const char* ver = last_slash + 1;

    int result = compare_versions(ver, target);

    return Py_BuildValue("i", result);
}

static PyMethodDef SemverMethods[] = {
    {"parse_and_compare",  parse_and_compare, METH_VARARGS, "Compare semver from URL."},
    {NULL, NULL, 0, NULL}
};

void initsemver_ext(void) {
    (void) Py_InitModule("semver_ext", SemverMethods);
}
EOF

    cat << 'EOF' > server.py
import http.server
import socketserver
import semver_ext
import sys

TARGET_VERSION = "1.2.0"

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        try:
            # Routing and parsing
            if self.path.startswith("/api/v1/pkg/"):
                valid = semver_ext.parse_and_compare(self.path, TARGET_VERSION)
                if valid:
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(b"Valid")
                else:
                    self.send_response(400)
                    self.end_headers()
                    self.wfile.write(b"Too old")
            else:
                self.send_response(404)
                self.end_headers()
        except Exception as e:
            self.send_response(500)
            self.end_headers()

if __name__ == "__main__":
    with socketserver.TCPServer(("127.0.0.1", 8080), Handler) as httpd:
        httpd.serve_forever()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
