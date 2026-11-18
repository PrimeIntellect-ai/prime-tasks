#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make wget nginx imagemagick tesseract-ocr
    pip3 install pytest

    # Create /app and generate coefficients.png
    mkdir -p /app
    convert -background white -fill black -pointsize 24 label:"A=2.5, B=1.2, C=0.3" /app/coefficients.png

    # Create directories
    mkdir -p /home/user/math_service
    mkdir -p /home/user/proxy

    # Create dummy static library
    cat << 'EOF' > /home/user/math_service/fastmath.cpp
int fast_init() { return 0; }
EOF
    g++ -c /home/user/math_service/fastmath.cpp -o /home/user/math_service/fastmath.o
    ar rcs /home/user/math_service/libfastmath.a /home/user/math_service/fastmath.o

    # Create server.cpp
    cat << 'EOF' > /home/user/math_service/server.cpp
// /home/user/math_service/server.cpp
#include "httplib.h"
#include <iostream>
#include <cmath>
// Requires linking with -pthread

int main() {
    httplib::Server svr;
    // TODO: Implement POST /compute

    svr.listen("127.0.0.1", 9090);
    return 0;
}
EOF

    # Create broken Makefile
    cat << 'EOF' > /home/user/math_service/Makefile
# /home/user/math_service/Makefile
# BUG: libfastmath.a is before server.cpp, missing -pthread
all:
	g++ libfastmath.a server.cpp -o server
EOF

    # Download httplib.h
    wget https://raw.githubusercontent.com/yhirose/cpp-httplib/master/httplib.h -O /home/user/math_service/httplib.h

    # Create verify.py
    cat << 'EOF' > /tmp/verify.py
import urllib.request
import json
import math

def true_f(x):
    return 2.5 * math.sin(x) + 1.2 * math.cos(x) + 0.3 * (x**2)

test_points = [0.0, 1.0, 2.5, 3.14, -1.5, 10.0]
mse = 0.0

try:
    for x in test_points:
        req = urllib.request.Request('http://127.0.0.1:8080/compute', method='POST')
        req.add_header('Content-Type', 'application/json')
        data = json.dumps({"x": x}).encode('utf-8')

        response = urllib.request.urlopen(req, data=data, timeout=2)
        result_json = json.loads(response.read().decode())

        predicted = result_json.get("result", 0.0)
        actual = true_f(x)
        mse += (predicted - actual) ** 2

    mse /= len(test_points)
    print(f"MSE: {mse}")
    if mse < 0.001:
        exit(0)
    else:
        exit(1)
except Exception as e:
    print(f"Error: {e}")
    exit(1)
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
