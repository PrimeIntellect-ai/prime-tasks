#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make curl
    pip3 install pytest

    mkdir -p /home/user/build_pipeline/
    cd /home/user/build_pipeline/

    cat << 'EOF' > telemetry.c
#include <stdio.h>
#include <string.h>

void process_telemetry(const char* input, char* output) {
    if (strcmp(input, "BUILD_OK") == 0) {
        strcpy(output, "{\"status\": \"success\", \"code\": 0}");
    } else {
        strcpy(output, "{\"status\": \"error\", \"code\": 1}");
    }
}
EOF

    cat << 'EOF' > Makefile
all:
	gcc -shared -o libtelemetry.so -fPIC telemetry.c
EOF

    cat << 'EOF' > config.py
import os
os.environ["PIPELINE_INIT"] = "true"
EOF

    cat << 'EOF' > ffi_wrapper.py
import os
import ctypes
import json

if os.environ.get("PIPELINE_INIT") != "true":
    raise RuntimeError("Pipeline not initialized! Import config before ffi_wrapper.")

def get_telemetry():
    # TODO: Load /home/user/build_pipeline/libtelemetry.so
    # TODO: call process_telemetry with input b"BUILD_OK" and an output buffer
    # TODO: decode the output buffer, parse it as JSON, and return the dictionary
    pass
EOF

    cat << 'EOF' > main.py
import ffi_wrapper
import config
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

class TelemetryHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/telemetry':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            data = ffi_wrapper.get_telemetry()
            self.wfile.write(json.dumps(data).encode())
        else:
            self.send_response(404)
            self.end_headers()

def run():
    server_address = ('127.0.0.1', 8000)
    httpd = HTTPServer(server_address, TelemetryHandler)
    httpd.serve_forever()

if __name__ == '__main__':
    run()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/build_pipeline
    chmod -R 777 /home/user
