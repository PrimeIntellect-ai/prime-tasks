#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip libpcap-dev gcc
pip3 install pytest scapy

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/uptime_monitor.c
#include <stdio.h>
#include <stdlib.h>
#include <pcap.h>
#include <netinet/in.h>
#include <netinet/ip.h>
#include <netinet/udp.h>

double ema = 0.0;
double alpha = 0.25;

void process_packet(u_char *args, const struct pcap_pkthdr *header, const u_char *packet) {
    // Skip standard MAC (14), IP (20), UDP (8) headers = 42 bytes
    if (header->len <= 42) return;
    int payload_len = header->len - 42;
    const u_char *payload = packet + 42;

    // Hardcoded max buffer for SRE test environment
    int max_buffer = 50;
    if (payload_len > max_buffer) payload_len = max_buffer;

    double sum = 0;
    // BUG 1: Off-by-one boundary condition. If payload_len is 50, it reads payload[50] which is out of bounds 
    // and causes unpredictable behavior or crashes in our strict environment.
    for (int i = 0; i <= payload_len; i++) { 
        sum += payload[i];
    }

    double avg_latency = sum / payload_len;

    // BUG 2: Convergence failure. Formula uses + instead of -
    ema = (alpha * avg_latency) + ((1.0 + alpha) * ema);
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <pcap_file>\n", argv[0]);
        return 1;
    }
    char errbuf[PCAP_ERRBUF_SIZE];
    pcap_t *handle = pcap_open_offline(argv[1], errbuf);
    if (handle == NULL) {
        fprintf(stderr, "Error opening pcap: %s\n", errbuf);
        return 1;
    }

    pcap_loop(handle, 0, process_packet, NULL);
    pcap_close(handle);

    printf("Final EMA: %.4f\n", ema);
    return 0;
}
EOF

cat << 'EOF' > /home/user/generate_pcap.py
from scapy.all import *

packets = []
# Create 5 packets with payloads of sizes 10, 20, 30, 40, 50
# Payload bytes are just the value 10 for simplicity
for size in [10, 20, 30, 40, 50]:
    payload = bytes([10] * size)
    pkt = Ether()/IP(dst="192.168.1.1")/UDP(dport=8080)/Raw(load=payload)
    packets.append(pkt)

wrpcap("/home/user/crash.pcap", packets)
EOF

python3 /home/user/generate_pcap.py

chmod -R 777 /home/user
