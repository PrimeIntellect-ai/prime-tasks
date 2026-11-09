#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest scapy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs
    cd /home/user

    # Create the log file
    cat << 'EOF' > /home/user/logs/uptime_monitor.log
2024-05-10 14:32:01 INFO Service metrics_processor started successfully.
2024-05-10 14:32:05 INFO Status check: OK.
2024-05-10 14:32:08 ERROR Service metrics_processor crashed unexpectedly (segmentation fault).
2024-05-10 14:32:10 INFO Attempting to restart service...
EOF

    # Create the buggy C++ code
    cat << 'EOF' > /home/user/metrics_processor.cpp
#include <iostream>
#include <vector>
#include <cstdint>
#include <cstring>

void process_metrics(const std::vector<uint8_t>& packet) {
    if (packet.size() < 5) return;

    uint32_t seq_id = *reinterpret_cast<const uint32_t*>(packet.data());
    uint8_t type = packet[4];

    if (type == 1) {
        // Normal metric
        if (packet.size() > 5) {
            std::cout << "Processing metric seq " << seq_id << "\n";
        }
    } else if (type == 2) {
        // High priority metric with text payload
        char local_buf[16];
        // BUG: No bounds checking. If packet size > 21, buffer overflow occurs.
        std::memcpy(local_buf, packet.data() + 5, packet.size() - 5);
        local_buf[15] = '\0'; // ensure null termination for print
        std::cout << "High priority metric seq " << seq_id << ": " << local_buf << "\n";
    }
}

int main() {
    // Simulated entry point
    std::cout << "Metrics processor running...\n";
    return 0;
}
EOF

    # Generate the pcap file using python
    cat << 'EOF' > /home/user/generate_pcap.py
from scapy.all import *
import struct
import time

packets = []

# Packet 1: Normal, Seq 100, Type 1
payload1 = struct.pack('<I', 100) + b'\x01' + b'data'
pkt1 = IP(dst="127.0.0.1")/UDP(dport=8080)/Raw(load=payload1)
pkt1.time = 1715351522.0 # 2024-05-10 14:32:02 UTC

# Packet 2: Normal, Seq 101, Type 1
payload2 = struct.pack('<I', 101) + b'\x01' + b'moredata'
pkt2 = IP(dst="127.0.0.1")/UDP(dport=8080)/Raw(load=payload2)
pkt2.time = 1715351526.0 # 2024-05-10 14:32:06 UTC

# Packet 3: Malicious/Malformed, Seq 102, Type 2, large payload to trigger buffer overflow
payload3 = struct.pack('<I', 102) + b'\x02' + (b'A' * 30)
pkt3 = IP(dst="127.0.0.1")/UDP(dport=8080)/Raw(load=payload3)
pkt3.time = 1715351527.95 # 2024-05-10 14:32:07.95 UTC

packets.extend([pkt1, pkt2, pkt3])
wrpcap('/home/user/capture.pcap', packets)
EOF
    python3 /home/user/generate_pcap.py
    rm /home/user/generate_pcap.py

    chmod -R 777 /home/user
