#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        g++ \
        diffutils

    pip3 install pytest flask requests

    mkdir -p /home/user/api_integration
    cd /home/user/api_integration

    cat << 'EOF' > backend_c.c
#include <stdio.h>
#include <string.h>

const char* get_data() {
    return "[{\"id\": 3, \"name\": \"Alice\", \"role\": \"admin\"}, {\"id\": 1, \"name\": \"Bob\", \"role\": \"user\"}, {\"id\": 2, \"name\": \"Charlie\", \"role\": \"moderator\"}]";
}
EOF

    cat << 'EOF' > backend_cpp.cpp
#include <iostream>
#include <string>

extern "C" {
    const char* get_data() {
        return "[{\"id\": 1, \"name\": \"Bob\", \"role\": \"user\"}, {\"id\": 3, \"name\": \"Alice\", \"role\": \"admin\"}, {\"id\": 2, \"name\": \"Charlie\", \"role\": \"moderator\"}]";
    }
}
EOF

    cat << 'EOF' > api.py
import ctypes
import json
from flask import Flask, jsonify

app = Flask(__name__)

@app.route('/api/v1/data')
def v1_data():
    try:
        lib = ctypes.CDLL('./libbackend_c.so')
        lib.get_data.restype = ctypes.c_char_p
        data = lib.get_data()
        return jsonify(json.loads(data.decode('utf-8')))
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/v2/data')
def v2_data():
    try:
        lib = ctypes.CDLL('./libbackend_cpp.so')
        lib.get_data.restype = ctypes.c_char_p
        data = lib.get_data()
        return jsonify(json.loads(data.decode('utf-8')))
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(port=5000)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
