#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc tshark tcpdump
    pip3 install pytest scapy

    useradd -m -s /bin/bash user || true

    # Setup git repository
    git config --global user.email "sre@example.com"
    git config --global user.name "SRE Admin"

    mkdir -p /home/user/uptime_tracker
    cd /home/user/uptime_tracker
    git init

    cat << 'EOF' > tracker.c
#include <stdio.h>
#include <stdlib.h>

#define WINDOW_SIZE 5

float calculate_rolling_average(float* window) {
    float sum = 0.0;
    // BUG: off by one (<= instead of <)
    for(int i = 0; i <= WINDOW_SIZE; i++) {
        sum += window[i];
        // TRACE LOGIC GOES HERE
    }
    return sum / WINDOW_SIZE;
}

int main() {
    float data[WINDOW_SIZE] = {99.9, 100.0, 95.5, 99.0, 98.2};
    float avg = calculate_rolling_average(data);
    printf("Average uptime: %.2f\n", avg);
    return 0;
}
EOF
    git add tracker.c
    git commit -m "Initial commit of tracker"

    cat << 'EOF' > secret.h
#define AUTH_SECRET "sre-core-auth-992x-alpha"
EOF
    git add secret.h
    git commit -m "Add authentication header"

    rm secret.h
    git add secret.h
    git commit -m "Remove secret.h to fix leak"

    # Generate PCAP file
    cat << 'EOF' > /tmp/gen_pcap.py
from scapy.all import *
pkts = []
for i in range(15):
    pkt = IP(dst="192.168.1.10")/TCP(dport=80)/Raw(load="GET /heartbeat HTTP/1.1\r\nHost: server\r\n\r\n")
    pkts.append(pkt)
for i in range(5):
    pkt = IP(dst="192.168.1.10")/TCP(dport=80)/Raw(load="GET /other HTTP/1.1\r\nHost: server\r\n\r\n")
    pkts.append(pkt)
wrpcap('/home/user/heartbeats.pcap', pkts)
EOF
    python3 /tmp/gen_pcap.py
    rm /tmp/gen_pcap.py

    chmod -R 777 /home/user
