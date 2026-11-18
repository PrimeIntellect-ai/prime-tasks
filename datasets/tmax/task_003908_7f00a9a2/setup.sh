#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make curl python2
    pip3 install pytest

    mkdir -p /app/vendored/libstrproc-1.0.2/src
    mkdir -p /app/api

    cat << 'EOF' > /app/vendored/libstrproc-1.0.2/src/strproc.c
#include <string.h>
#include <ctype.h>

void process_string(const char* input, char* output) {
    char buf[256];
    strcpy(buf, input);
    for(int i = 0; buf[i]; i++) {
        output[i] = toupper(buf[i]);
    }
    output[strlen(buf)] = '\0';
}
EOF

    cat << 'EOF' > /app/vendored/libstrproc-1.0.2/Makefile
all:
	gcc -shared -o libstrproc.so -fPIC src/strproc.c
EOF

    cat << 'EOF' > /app/api/wrapper.py
import ctypes
import os

lib_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '../vendored/libstrproc-1.0.2/libstrproc.so'))
lib = ctypes.CDLL(lib_path)

def process(input_str):
    out_buf = ctypes.create_string_buffer(len(input_str) + 1)
    lib.process_string(input_str, out_buf)
    return out_buf.value
EOF

    cat << 'EOF' > /app/api/server.py
import BaseHTTPServer
import json
from wrapper import process

class Handler(BaseHTTPServer.BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/process':
            content_length = int(self.headers.getheader('content-length', 0))
            body = self.rfile.read(content_length)
            data = json.loads(body)
            input_str = data.get('input', '')

            res_str = process(input_str)

            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'result': res_str}))
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = BaseHTTPServer.HTTPServer(('127.0.0.1', 8080), Handler)
    print "Starting server on port 8080"
    server.serve_forever()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
