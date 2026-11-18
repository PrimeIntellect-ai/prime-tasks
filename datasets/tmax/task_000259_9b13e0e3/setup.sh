#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /app/tinymath

    cat << 'EOF' > /app/tinymath/tinymath.c
#include <math.h>
#include <stdio.h>
#include <string.h>

const char* get_version() {
    return "1.2.0";
}

double evaluate(const char* expr) {
    double val1 = 0, val2 = 0;
    char func[10] = {0};
    char op = 0;

    if (sscanf(expr, "%[a-z](%lf) %c %lf", func, &val1, &op, &val2) == 4) {
        double res = 0;
        if (strcmp(func, "sin") == 0) res = sin(val1);
        else if (strcmp(func, "cos") == 0) res = cos(val1);
        else res = val1;

        if (op == '+') return res + val2;
        if (op == '*') return res * val2;
        if (op == '-') return res - val2;
        if (op == '/') return res / val2;
    }
    return 0.0;
}
EOF

    cat << 'EOF' > /app/tinymath/Makefile
all: libtinymath.so

libtinymath.so: tinymath.o
	gcc -shared -fPIC -o libtinymath.so tinymath.o

tinymath.o: tinymath.c
	gcc -c -fPIC tinymath.c -o tinymath.o

clean:
	rm -f *.o *.so
EOF

    cat << 'EOF' > /app/server.py
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import ctypes
import os

def check_version(lib):
    lib.get_version.restype = ctypes.c_char_p
    version = lib.get_version().decode('utf-8')

    parts = version.split('.')
    # Buggy check
    if int(parts[0]) >= 1 and int(parts[1]) > 2:
        return True
    return False

class MathServer(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/evaluate':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            req = json.loads(post_data)
            expr = req.get("expression", "")

            lib = ctypes.CDLL("/app/tinymath/libtinymath.so")
            lib.evaluate.restype = ctypes.c_double
            lib.evaluate.argtypes = [ctypes.c_char_p]

            res = lib.evaluate(expr.encode('utf-8'))

            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"result": res}).encode('utf-8'))

if __name__ == '__main__':
    try:
        lib = ctypes.CDLL("/app/tinymath/libtinymath.so")
    except Exception as e:
        print(f"Failed to load library: {e}")
        sys.exit(1)

    if not check_version(lib):
        print("Version check failed! Required >= 1.2.0")
        sys.exit(1)

    server_address = ('127.0.0.1', 8080)
    httpd = HTTPServer(server_address, MathServer)
    httpd.serve_forever()
EOF

    cd /app/tinymath && make || true

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
