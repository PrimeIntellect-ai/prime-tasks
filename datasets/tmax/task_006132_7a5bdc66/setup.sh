#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip haproxy gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/test_env

    cat << 'EOF' > /home/user/test_env/server.py
import http.server
import socketserver
import ctypes
import json
import os

class Record(ctypes.Structure):
    _fields_ = [
        ("record_id", ctypes.c_uint32),
        ("decoded_text", ctypes.c_char * 64)
    ]

class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length).decode('utf-8')

        lib_path = '/home/user/test_env/libtelemetry.so'
        if not os.path.exists(lib_path):
            self.send_error(500, "Shared library not found")
            return

        lib = ctypes.CDLL(lib_path)
        lib.process_record.argtypes = [ctypes.c_char_p, ctypes.POINTER(Record)]
        lib.process_record.restype = ctypes.c_int

        record = Record()
        res = lib.process_record(post_data.encode('utf-8'), ctypes.byref(record))

        if res == 0:
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            resp = {"id": record.record_id, "text": record.decoded_text.decode('utf-8')}
            self.wfile.write(json.dumps(resp).encode('utf-8'))
        else:
            self.send_error(400, "Processing failed")

with socketserver.TCPServer(("127.0.0.1", 9000), Handler) as httpd:
    httpd.serve_forever()
EOF

    chmod -R 777 /home/user
