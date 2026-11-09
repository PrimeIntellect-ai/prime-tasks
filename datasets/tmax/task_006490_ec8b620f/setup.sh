#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest scapy

    mkdir -p /home/user/src /home/user/logs

    cat << 'EOF' > /home/user/src/server.cpp
#include <iostream>
#include <string>
#include <thread>
#include <mutex>
#include <vector>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
#include <cstring>

std::mutex mutex_A;
std::mutex mutex_B;

std::map<std::string, int> stats;

void process_packet(const std::string& payload) {
    if (payload.find("TYPE_A") == 0) {
        std::lock_guard<std::mutex> lock1(mutex_A);
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
        std::lock_guard<std::mutex> lock2(mutex_B);
        stats[payload]++;
    } else if (payload.find("TYPE_B") == 0) {
        std::lock_guard<std::mutex> lock1(mutex_B);
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
        std::lock_guard<std::mutex> lock2(mutex_A);
        stats[payload]++;
    }
}

int main() {
    int sockfd = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in servaddr;
    memset(&servaddr, 0, sizeof(servaddr));
    servaddr.sin_family = AF_INET;
    servaddr.sin_addr.s_addr = INADDR_ANY;
    servaddr.sin_port = htons(9000);

    bind(sockfd, (const struct sockaddr *)&servaddr, sizeof(servaddr));

    char buffer[1024];
    while (true) {
        int n = recvfrom(sockfd, (char *)buffer, 1024, MSG_WAITALL, NULL, NULL);
        if (n > 0) {
            buffer[n] = '\0';
            std::string payload(buffer);
            std::thread(process_packet, payload).detach();
        }
    }
    close(sockfd);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/src/Makefile
server: server.cpp
	g++ -std=c++14 server.cpp -o server -pthread
EOF

    cat << 'EOF' > /tmp/gen_pcap.py
from scapy.all import *
pkts = []
# Background traffic
pkts.append(IP(src="10.0.0.5", dst="10.0.0.1")/UDP(dport=9000)/Raw(load="TYPE_C_NORMAL_LOG"))
pkts.append(IP(src="10.0.0.6", dst="10.0.0.1")/UDP(dport=9000)/Raw(load="TYPE_C_NORMAL_LOG2"))
# The attacker traffic
pkts.append(IP(src="172.16.44.99", dst="10.0.0.1")/UDP(sport=12345, dport=9000)/Raw(load="TYPE_A_DEADLOCK_TRIGGER"))
pkts.append(IP(src="172.16.44.99", dst="10.0.0.1")/UDP(sport=12345, dport=9000)/Raw(load="TYPE_B_DEADLOCK_TRIGGER"))
# More background
pkts.append(IP(src="10.0.0.7", dst="10.0.0.1")/UDP(dport=9000)/Raw(load="TYPE_C_NORMAL_LOG3"))
wrpcap('/home/user/logs/crash_traffic.pcap', pkts)
EOF

    python3 /tmp/gen_pcap.py
    rm /tmp/gen_pcap.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
