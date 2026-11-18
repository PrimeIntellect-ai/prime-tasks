#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake make g++
    pip3 install pytest flask

    mkdir -p /home/user/math_api/src
    mkdir -p /home/user/math_api/api
    mkdir -p /home/user/math_api/tests
    mkdir -p /home/user/math_api/build

    cat << 'EOF' > /home/user/math_api/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(MathOps)
set(CMAKE_CXX_STANDARD 14)
add_library(math_ops SHARED src/math_ops.cpp)
EOF

    cat << 'EOF' > /home/user/math_api/src/math_ops.cpp
#include <cmath>

double calculate_hypotenuse(double a, double b) {
    return std::sqrt(a*a + b*b);
}
EOF

    cat << 'EOF' > /home/user/math_api/api/app.py
from flask import Flask, jsonify
import ctypes
import os

app = Flask(__name__)

# Load the shared library
lib_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '../build/libmath_ops.so'))
math_lib = ctypes.CDLL(lib_path)
math_lib.calculate_hypotenuse.argtypes = [ctypes.c_double, ctypes.c_double]
math_lib.calculate_hypotenuse.restype = ctypes.c_double

@app.route('/api/hypotenuse/<a>/<b>')
def hypotenuse(a, b):
    result = math_lib.calculate_hypotenuse(a, b)
    return jsonify({"result": result})

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /home/user/math_api/tests/test_api.py
import pytest
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from api.app import app

@pytest.fixture
def client():
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client

def test_hypotenuse(client):
    response = client.get('/api/hypotenuse/3.0/4.0')
    assert response.status_code == 200
    assert response.get_json() == {"result": 5.0}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/math_api
    chmod -R 777 /home/user
