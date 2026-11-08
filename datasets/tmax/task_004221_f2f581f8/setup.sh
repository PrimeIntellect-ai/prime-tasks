#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ redis-server curl libfcgi-dev spawn-fcgi
    pip3 install pytest flask redis requests

    mkdir -p /home/user/build_tools
    mkdir -p /home/user/services
    mkdir -p /app/oracle

    cat << 'EOF' > /home/user/build_tools/checksum_engine.cpp
#include <iostream>
#include <vector>

int main() {
    int* p = new int[10];
    for (int i = 0; i <= 10; ++i) p[i] = 0; // off-by-one
    delete[] p;
    delete[] p; // double-free
    return 0;
}
EOF

    cat << 'EOF' > /home/user/services/resolver.py
from flask import Flask, request, jsonify
import redis
import requests
import os

app = Flask(__name__)

@app.route('/resolve', methods=['POST'])
def resolve():
    return jsonify({"status": "ok", "checksum": "1234"})

if __name__ == '__main__':
    app.run(port=8001)
EOF

    cat << 'EOF' > /home/user/services/start_pipeline.sh
#!/bin/bash
# Start script
EOF
    chmod +x /home/user/services/start_pipeline.sh

    cat << 'EOF' > /tmp/checksum_reference.cpp
#include <iostream>
int main() {
    std::cout << "deadbeef" << std::endl;
    return 0;
}
EOF
    g++ -O2 /tmp/checksum_reference.cpp -o /app/oracle/checksum_reference.bin
    chmod +x /app/oracle/checksum_reference.bin

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
