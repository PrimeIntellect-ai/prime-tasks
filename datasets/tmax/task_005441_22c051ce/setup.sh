#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ gdb tshark tcpdump
    pip3 install pytest scapy

    mkdir -p /app/corpora/clean /app/corpora/evil

    # Create the vulnerable C++ program
    cat << 'EOF' > /tmp/log_ingester.cpp
#include <iostream>
#include <string>
#include <cstring>

void process_log(const std::string& line) {
    char app_name[16];
    size_t start = line.find("] [");
    if (start != std::string::npos) {
        start += 3;
        size_t end = line.find("]", start);
        if (end != std::string::npos) {
            std::string name = line.substr(start, end - start);
            strcpy(app_name, name.c_str());
        }
    }
}

int main() {
    std::string line;
    while (std::getline(std::cin, line)) {
        process_log(line);
    }
    return 0;
}
EOF

    # Compile the binary without stack protections and strip it
    g++ -fno-stack-protector -z execstack -no-pie -s -o /app/log_ingester /tmp/log_ingester.cpp
    chmod +x /app/log_ingester

    # Generate the core dump
    cd /app
    ulimit -c unlimited
    echo "[2023-10-12 08:14:02] [VERYLONGAPPNAMEEXCEEDING16BYTES123456789012345678901234567890] Failed to connect to DB" | ./log_ingester || true
    find . -name "core*" -exec mv {} crash.core \;
    if [ ! -f crash.core ]; then
        touch crash.core
    fi

    # Generate the PCAP file
    cat << 'EOF' > /tmp/gen_pcap.py
from scapy.all import *
pkt = IP(dst="127.0.0.1")/UDP(dport=514)/Raw(load=b"[2023-10-12 08:14:02] [VERYLONGAPPNAMEEXCEEDING16BYTES] Failed to connect to DB")
wrpcap("/app/traffic.pcap", [pkt])
EOF
    python3 /tmp/gen_pcap.py

    # Create corpora
    cat << 'EOF' > /app/corpora/clean/clean.log
[2023-10-12 08:14:00] [NGINX] GET / index.html
[2023-10-12 08:14:01] [POSTGRES_DB] Connection established
EOF

    cat << 'EOF' > /app/corpora/evil/evil.log
[2023-10-12 08:14:02] [THIS_IS_A_VERY_LONG_APP_NAME] Something went wrong
[2023-10-12 08:14:03] [ANOTHER_OVERSIZED_APP_NAME_HERE] Exploit attempt
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
