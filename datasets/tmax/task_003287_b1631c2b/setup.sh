#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libhiredis-dev redis-server
    pip3 install pytest

    mkdir -p /home/user/app
    mkdir -p /opt/oracle

    # Create log_aggregator.cpp with intentional bugs
    cat << 'EOF' > /home/user/app/log_aggregator.cpp
#include <iostream>
#include <string>
#include <vector>
#include <thread>
// Missing <mutex> for build error

double total_sum = 0.0;
int count_events = 0;

void process_log(const std::string& log) {
    // Flawed parsing that crashes on negative exponent
    size_t e_pos = log.find('e');
    if (e_pos != std::string::npos) {
        if (log[e_pos+1] == '-') {
            // Simulate crash
            char* crash = nullptr;
            *crash = 'x';
        }
    }
    // Race condition
    total_sum += 1.0;
    count_events++;
}

int main(int argc, char** argv) {
    std::cout << "Starting log aggregator..." << std::endl;
    return 0;
}
EOF

    # Create dummy core dump
    echo "DUMMY CORE DUMP" > /home/user/app/core

    # Create log_generator.py
    cat << 'EOF' > /home/user/app/log_generator.py
#!/usr/bin/env python3
import socket
import time
import random

def start_server():
    pass

if __name__ == "__main__":
    start_server()
EOF
    chmod +x /home/user/app/log_generator.py

    # Create oracle
    cat << 'EOF' > /opt/oracle/log_aggregator_oracle
#!/bin/bash
echo "Oracle"
EOF
    chmod +x /opt/oracle/log_aggregator_oracle

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /opt/oracle
