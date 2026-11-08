#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ cmake nlohmann-json3-dev libcpp-httplib-dev curl
    pip3 install pytest flask requests aiohttp

    mkdir -p /home/user/app/proxy
    mkdir -p /home/user/app/backend
    mkdir -p /home/user/app/tester

    cat << 'EOF' > /home/user/app/proxy/main.cpp
#include <iostream>
int main() {
    std::cout << "Naive proxy running..." << std::endl;
    return 0;
}
EOF

    cat << 'EOF' > /home/user/app/proxy/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(Proxy)
set(CMAKE_CXX_STANDARD 17)
add_executable(proxy main.cpp)
EOF

    cat << 'EOF' > /home/user/app/backend/server.py
from flask import Flask
app = Flask(__name__)
if __name__ == '__main__':
    app.run(port=8081)
EOF

    cat << 'EOF' > /home/user/app/tester/benchmark.py
import sys
print("Throughput: 0 req/s")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
