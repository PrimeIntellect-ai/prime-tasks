#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest requests

    mkdir -p /home/user/project

    cat << 'EOF' > /home/user/project/server.py
from http.server import BaseHTTPRequestHandler, HTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/token':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            # 40 character payload
            self.wfile.write(b"TOKEN_RESPONSE_88442211_LONG_PAYLOAD_XYZ")
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8080), Handler)
    server.serve_forever()
EOF

    cat << 'EOF' > /home/user/project/processor.c
#include <string.h>
#include <stdio.h>

void process_payload(const char* input, char* output) {
    // BUG: Buffer is too small for the 40-character payload, causing a buffer overflow
    char temp_buffer[16]; 

    // Copy input to temp (UNSAFE)
    strcpy(temp_buffer, input);

    // Reverse the string into output (just some arbitrary processing)
    int len = strlen(temp_buffer);
    for(int i = 0; i < len; i++) {
        output[i] = temp_buffer[len - 1 - i];
    }
    output[len] = '\0';
}
EOF

    cat << 'EOF' > /home/user/project/legacy_client.js
// Broken legacy script - requires outdated unresolvable npm packages
const request = require('deprecated-request-lib');
const ffi = require('ffi-napi');

// Setup FFI
const lib = ffi.Library('./libprocessor', {
  'process_payload': [ 'void', [ 'string', 'string' ] ]
});

request('http://127.0.0.1:8080/api/token', function (error, response, body) {
  let outBuffer = Buffer.alloc(256);
  lib.process_payload(body, outBuffer);
  console.log("Result:", outBuffer.toString('utf8'));
});
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
