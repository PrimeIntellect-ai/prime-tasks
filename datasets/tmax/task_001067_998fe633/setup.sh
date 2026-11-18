#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake g++ make redis-server
    pip3 install pytest flask redis

    mkdir -p /home/user/workspace/src
    mkdir -p /home/user/workspace/api
    mkdir -p /home/user/workspace/build

    # Create oracle
    cat << 'EOF' > /home/user/oracle.c
#include <stdio.h>
#include <stdint.h>
#include <string.h>
uint32_t compute_hash(const char* data, size_t len) {
    uint32_t hash = 5381;
    for (size_t i = 0; i < len; ++i) {
        hash = ((hash << 5) + hash) + data[i];
    }
    return hash;
}
int main(int argc, char** argv) {
    if (argc > 1) {
        printf("%u\n", compute_hash(argv[1], strlen(argv[1])));
    }
    return 0;
}
EOF
    gcc -O3 /home/user/oracle.c -o /home/user/oracle_hash
    rm /home/user/oracle.c

    # Create workspace files
    cat << 'EOF' > /home/user/workspace/src/hash.cpp
#include <cstdint>
#include <cstddef>

extern "C" {
    uint32_t compute_hash(const char* data, size_t len) {
        uint32_t hash = 5381;
        for (size_t i = 0; i < len; ++i) {
            hash = ((hash << 4) + hash) + data[i];
        }
        return hash;
    }
}
EOF

    cat << 'EOF' > /home/user/workspace/src/main.cpp
#include <iostream>
#include <cstring>
#include <cstdint>

extern "C" uint32_t compute_hash(const char* data, size_t len);

int main(int argc, char** argv) {
    if (argc > 1) {
        std::cout << compute_hash(argv[1], std::strlen(argv[1])) << std::endl;
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/workspace/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(MathOps)

add_library(mathops SHARED src/hash.cpp)
# Missing POSITION_INDEPENDENT_CODE

add_executable(compute_hash src/main.cpp)
# Missing target_link_libraries
EOF

    cat << 'EOF' > /home/user/workspace/api/app.py
from flask import Flask, request, jsonify
import ctypes
import redis
import os

app = Flask(__name__)

# Broken connection string
cache = redis.Redis(host='redis', port=6379)

lib_path = os.path.join(os.path.dirname(__file__), '../build/libmathops.so')
try:
    mathops = ctypes.CDLL(lib_path)
    # Broken argtypes and restype
    mathops.compute_hash.argtypes = [ctypes.c_char_p]
    mathops.compute_hash.restype = ctypes.c_int
except Exception as e:
    mathops = None

@app.route('/hash', methods=['POST'])
def hash_endpoint():
    data = request.form.get('data', '')
    if not data:
        return jsonify({'error': 'No data provided'}), 400

    try:
        cached_val = cache.get(data)
        if cached_val:
            return jsonify({'hash': int(cached_val), 'cached': True})
    except:
        pass

    if mathops:
        b_data = data.encode('utf-8')
        h = mathops.compute_hash(b_data, len(b_data))
        try:
            cache.set(data, h)
        except:
            pass
        return jsonify({'hash': h, 'cached': False})
    return jsonify({'error': 'Library not loaded'}), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
