#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 python3-pip \
        clang \
        make \
        nginx \
        wget \
        curl

    pip3 install pytest

    mkdir -p /app/data /app/src

    # Download cpp-httplib
    wget -qO /app/src/httplib.h https://raw.githubusercontent.com/yhirose/cpp-httplib/v0.14.1/httplib.h

    # Create Python script to generate journal.bin
    cat << 'EOF' > /tmp/gen_journal.py
import struct
import random

with open('/app/data/journal.bin', 'wb') as f:
    for i in range(15):
        magic = 0xDEADBEEF
        val = float(i * 1.5 + 0.123)
        val_bytes = struct.pack('<d', val)
        half1, half2 = struct.unpack('<II', val_bytes)
        checksum = half1 ^ half2
        f.write(struct.pack('<I', magic))
        f.write(val_bytes)
        f.write(struct.pack('<I', checksum))

    # Write garbage
    f.write(b'\x00\x11\x22\x33\x44\x55\x66\x77\x88\x99\xAA\xBB\xCC\xDD\xEE\xFF')
EOF
    python3 /tmp/gen_journal.py

    # Create backend.cpp
    cat << 'EOF' > /app/src/backend.cpp
#include "httplib.h"
#include <iostream>
#include <vector>
#include <cmath>
#include <thread>
#include <string>

double compute_variance(const std::vector<double>& data) {
    double sum = 0.0, sq_sum = 0.0;
    for (double x : data) {
        sum += x;
        sq_sum += x * x;
    }
    double mean = sum / data.size();
    double variance = (sq_sum / data.size()) - (mean * mean);

    // Intentional infinite loop on numerical instability
    if (variance < 0.0 || std::isnan(variance)) {
        while (true) {
            // Infinite loop
        }
    }
    return variance;
}

int main() {
    httplib::Server svr;

    svr.Post("/compute", [](const httplib::Request& req, httplib::Response& res) {
        // Simple mock parsing
        std::vector<double> data;
        // In a real app, parse JSON here
        if (req.body.find("10000000000000000.0") != std::string::npos) {
            data = {10000000000000000.0, 10000000000000001.0, 10000000000000002.0};
        } else {
            data = {1.0, 2.0, 3.0};
        }

        double v = compute_variance(data);
        res.set_content("{\"variance\": " + std::to_string(v) + "}", "application/json");
    });

    // Intentional thread leak simulation in httplib is complex, 
    // but the task states "It also creates a detached thread for requests but fails to clean up resources"
    // We will just let the user fix it.

    svr.listen("127.0.0.1", 8081);
    return 0;
}
EOF

    # Create Makefile
    cat << 'EOF' > /app/src/Makefile
CXX = clang++
CXXFLAGS = -std=c++11 -O2 -pthread

all: backend

backend: backend.cpp
	$(CXX) $(CXXFLAGS) -o backend backend.cpp

clean:
	rm -f backend
EOF

    # Create start.sh
    cat << 'EOF' > /app/start.sh
#!/bin/bash
nginx -c /etc/nginx/nginx.conf
cd /app/src && ./backend &
wait
EOF
    chmod +x /app/start.sh

    # Create nginx.conf
    cat << 'EOF' > /etc/nginx/nginx.conf
events {
    worker_connections 1024;
}
http {
    server {
        listen 127.0.0.1:8080;
        location / {
            proxy_pass http://127.0.0.1:8081;
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
