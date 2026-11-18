#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ socat valgrind curl
pip3 install pytest

mkdir -p /home/user/app

cat << 'EOF' > /home/user/app/libbackend.cpp
#include <cstring>

extern "C" {
    char* process_data(const char* input) {
        // BUG: Allocates new memory every time, causing a leak because python ctypes char_p doesn't free it.
        char* result = new char[256];
        strncpy(result, "Processed: ", 256);
        strncat(result, input, 256 - strlen(result) - 1);
        return result;
    }
}
EOF

cat << 'EOF' > /home/user/app/server.py
import ctypes
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

lib = ctypes.CDLL(os.path.abspath('/home/user/app/libbackend.so'))
lib.process_data.argtypes = [ctypes.c_char_p]
lib.process_data.restype = ctypes.c_char_p

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        result = lib.process_data(b"Test Data")
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        self.wfile.write(result)

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 9000), RequestHandler)
    server.serve_forever()
EOF

cat << 'EOF' > /home/user/verify.sh
#!/bin/bash

# Check if library exists
if [ ! -f /home/user/app/libbackend.so ]; then
    echo "Verification failed: libbackend.so not found."
    exit 1
fi

# Check valgrind output for zero leaks
if grep -q "definitely lost: 0 bytes" /home/user/app/valgrind_fixed.log; then
    echo "Memory leak fixed."
else
    echo "Verification failed: memory leak still present or valgrind log missing."
    exit 1
fi

echo "All tests passed."
EOF
chmod +x /home/user/verify.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
