#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ netcat-openbsd
    pip3 install pytest

    mkdir -p /home/user/data/subdir

    # Create some dummy files to be measured
    dd if=/dev/urandom of=/home/user/data/file1.bin bs=1024 count=1500 2>/dev/null
    dd if=/dev/urandom of=/home/user/data/subdir/file2.bin bs=1024 count=2500 2>/dev/null
    echo "Hello World" > /home/user/data/text.txt

    # Create metrics server
    cat << 'EOF' > /home/user/metrics_server.py
import socket
import time
import sys
import os

time.sleep(2) # Simulate slow startup
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind(('127.0.0.1', 9090))
sock.listen(1)

conn, addr = sock.accept()
data = conn.recv(1024).decode('utf-8')
with open('/home/user/server.log', 'w') as f:
    f.write(data)
conn.close()
EOF
    chmod +x /home/user/metrics_server.py

    # Create buggy supervisor
    cat << 'EOF' > /home/user/supervisor.sh
#!/bin/bash
python3 /home/user/metrics_server.py &
SERVER_PID=$!

# BUG: Starts immediately without waiting for port 9090
/home/user/capacity_planner &
PLANNER_PID=$!

wait $SERVER_PID
wait $PLANNER_PID
EOF
    chmod +x /home/user/supervisor.sh

    # Create skeleton C++ file
    cat << 'EOF' > /home/user/capacity_planner.cpp
#include <iostream>
#include <filesystem>
#include <string>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <unistd.h>

namespace fs = std::filesystem;

int main() {
    std::string data_dir = "/home/user/data";
    long long total_size = 0;

    // TODO: Recursively calculate total_size of data_dir

    // TODO: Connect to 127.0.0.1:9090
    // TODO: Send "CAPACITY:<total_size>\n"
    // TODO: If connection fails, exit with code 1

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
