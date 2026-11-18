#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libpcap-dev strace tcpdump g++
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_pcap.py
import struct
import time

# PCAP Global Header
# Magic Number, Major, Minor, ThisZone, SigFigs, SnapLen, Network (1 = Ethernet)
global_header = struct.pack('<IHHIIII', 0xa1b2c3d4, 2, 4, 0, 0, 65535, 1)

def build_packet(sensor_id, value):
    # Ethernet Header (14 bytes)
    eth = b'\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x08\x00'
    # IPv4 Header (20 bytes)
    ip = b'\x45\x00\x00\x28\x00\x00\x40\x00\x40\x11\x00\x00\x7f\x00\x00\x01\x7f\x00\x00\x01'
    # UDP Header (8 bytes)
    udp = b'\x30\x39\x30\x39\x00\x14\x00\x00'

    # Payload (12 bytes)
    payload = struct.pack('>Id', sensor_id, value)

    packet_data = eth + ip + udp + payload

    # PCAP Packet Header
    ts_sec = int(time.time())
    ts_usec = 0
    incl_len = len(packet_data)
    orig_len = len(packet_data)
    pkt_header = struct.pack('<IIII', ts_sec, ts_usec, incl_len, orig_len)

    return pkt_header + packet_data

with open('/home/user/traffic.pcap', 'wb') as f:
    f.write(global_header)
    f.write(build_packet(101, 12345.678901))
    f.write(build_packet(102, 98765.432109))
    f.write(build_packet(103, 0.000001))
EOF

    python3 /home/user/generate_pcap.py

    cat << 'EOF' > /home/user/telemetry_ingest.cpp
#include <iostream>
#include <fstream>
#include <pcap.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <cstring>
#include <unistd.h>
#include <fcntl.h>

void process_packet(u_char *args, const struct pcap_pkthdr *header, const u_char *packet) {
    int fd = *(int*)args;
    // Skip Ethernet(14), IP(20), UDP(8)
    const u_char *payload = packet + 14 + 20 + 8;

    uint32_t sensor_id;
    memcpy(&sensor_id, payload, 4);
    sensor_id = ntohl(sensor_id);

    // BUG 2: Precision loss and wrong type cast
    uint32_t val_raw;
    memcpy(&val_raw, payload + 4, 4); // Only reading 4 bytes!
    val_raw = ntohl(val_raw);
    float value;
    memcpy(&value, &val_raw, 4);

    char buffer[256];
    int len = snprintf(buffer, sizeof(buffer), "Sensor %u: %.6f\n", sensor_id, value);
    write(fd, buffer, len);
}

int main() {
    char errbuf[PCAP_ERRBUF_SIZE];
    pcap_t *handle = pcap_open_offline("/home/user/traffic.pcap", errbuf);
    if (handle == nullptr) {
        return 1;
    }

    // BUG 1: Failing system call due to permission
    int fd = open("/root/telemetry.out", O_CREAT | O_WRONLY | O_TRUNC, 0644);
    if (fd < 0) {
        return 1; // Fails silently
    }

    pcap_loop(handle, 0, process_packet, (u_char*)&fd);

    close(fd);
    pcap_close(handle);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
