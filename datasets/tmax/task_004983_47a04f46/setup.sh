#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make curl
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/vm.c
#include <string.h>

int evaluate(const char* bytecode) {
    int acc = 0;
    int len = strlen(bytecode);
    for(int i = 0; i < len; i += 2) {
        char op = bytecode[i];
        int val = bytecode[i+1] - '0';
        if(op == 'P') acc += val;
        else if(op == 'M') acc -= val;
    }
    return acc;
}
EOF

    cat << 'EOF' > /home/user/Makefile
libvm.so: vm.c
	gcc -shared -o libvm.so -fPIC vm.c
EOF

    cat << 'EOF' > /home/user/api.py
import ctypes
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs
import os

# Load library
lib = ctypes.CDLL(os.path.abspath('./libvm.so'))

# BUG: Missing FFI definitions. The agent needs to add:
# lib.evaluate.argtypes = [ctypes.c_char_p]
# lib.evaluate.restype = ctypes.c_int

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == '/eval':
            qs = parse_qs(parsed.query)
            if 'code' in qs:
                # BUG: String passed directly to C function without byte encoding
                # Fix: code = qs['code'][0].encode('utf-8')
                code = qs['code'][0]

                try:
                    res = lib.evaluate(code) # Agent must fix this invocation
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(str(res).encode('utf-8'))
                    return
                except Exception as e:
                    self.send_response(500)
                    self.end_headers()
                    self.wfile.write(b'Internal Server Error')
                    return

        self.send_response(404)
        self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8080), Handler)
    server.serve_forever()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
