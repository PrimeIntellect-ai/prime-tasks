#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ make socat curl
pip3 install pytest

mkdir -p /home/user/project
cd /home/user/project

# Create the broken C++ file
cat << 'EOF' > processor.cpp
#include <iostream>
#include <string>
#include <vector>
#include <algorithm>
#include <cstring>

struct Item {
    int id;
    std::string val;
};

// Intentionally missing C-linkage and returning std::string directly
std::string sort_items(const char* input_json) {
    // Very simplified parser for the specific test case
    // Input: [{"id": 3, "val": "C"}, {"id": 1, "val": "A"}, {"id": 2, "val": "B"}]
    std::string s(input_json);
    std::vector<Item> items;

    // Hardcoded extraction for simplicity in this task
    items.push_back({3, "C"});
    items.push_back({1, "A"});
    items.push_back({2, "B"});

    std::sort(items.begin(), items.end(), [](const Item& a, const Item& b) {
        return a.id < b.id;
    });

    std::string result = "[";
    for (size_t i = 0; i < items.size(); ++i) {
        result += "{\"id\": " + std::to_string(items[i].id) + ", \"val\": \"" + items[i].val + "\"}";
        if (i < items.size() - 1) result += ", ";
    }
    result += "]";

    return result; // Compilation/FFI error: returns std::string instead of const char*
}
EOF

# Create Makefile
cat << 'EOF' > Makefile
all:
	g++ -fPIC -shared -o libprocessor.so processor.cpp
EOF

# Create Python server
cat << 'EOF' > server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import ctypes
import json

# Load the shared library
lib = ctypes.CDLL('./libprocessor.so')

# Intentional FFI error: Missing restype setup for the C function
# lib.sort_items.restype = ctypes.c_char_p
lib.sort_items.argtypes = [ctypes.c_char_p]

class RequestHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)

        # Call C++ function
        result_ptr = lib.sort_items(post_data)

        # Result needs to be cast properly if restype is missing, but fixing restype is the task
        if isinstance(result_ptr, int):
            result = ctypes.cast(result_ptr, ctypes.c_char_p).value.decode('utf-8')
        else:
            result = result_ptr.decode('utf-8')

        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(result.encode('utf-8'))

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8080), RequestHandler)
    server.serve_forever()
EOF

chmod +x Makefile

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
