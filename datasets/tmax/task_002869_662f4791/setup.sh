#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git build-essential libpcap-dev gdb espeak
    pip3 install pytest scapy

    mkdir -p /app
    espeak -w /app/briefing.wav "Make sure the extractor always listens on UDP port eight zero eight zero."

    mkdir -p /home/user/repo
    cd /home/user/repo
    git init
    git config user.name "Dev"
    git config user.email "dev@example.com"

    cat << 'EOF' > Makefile
CXX=g++
CXXFLAGS=-Wall -O2
LDFLAGS=-lpcap

all: pcap-extractor

pcap-extractor: extractor.cpp
	$(CXX) $(CXXFLAGS) -o pcap-extractor extractor.cpp $(LDFLAGS)

clean:
	rm -f pcap-extractor
EOF

    cat << 'EOF' > extractor.cpp
#include <iostream>
#include <fstream>
#include <pcap.h>
#include <netinet/in.h>
#include <netinet/ip.h>
#include <netinet/udp.h>
#include <net/ethernet.h>

using namespace std;

int target_port = 0;
ofstream out;

void packet_handler(u_char *args, const struct pcap_pkthdr *header, const u_char *packet) {
    struct ether_header *eth_header;
    eth_header = (struct ether_header *) packet;
    if (ntohs(eth_header->ether_type) != ETHERTYPE_IP) return;

    const u_char *ip_header = packet + 14;
    int ip_header_length = ((*ip_header) & 0x0F) * 4;
    u_char protocol = *(ip_header + 9);
    if (protocol != IPPROTO_UDP) return;

    struct udphdr *udp_header = (struct udphdr *)(ip_header + ip_header_length);
    int dest_port = ntohs(udp_header->dest);
    if (dest_port != target_port) return;

    int payload_length = ntohs(udp_header->len) - 8;
    const u_char *payload = (u_char *)udp_header + 8;

    for (int i = 0; i < payload_length; i++) {
        out.put(payload[i]);
    }
}

int main(int argc, char *argv[]) {
    if (argc != 4) return 1;
    target_port = atoi(argv[1]);
    char errbuf[PCAP_ERRBUF_SIZE];
    pcap_t *handle = pcap_open_offline(argv[2], errbuf);
    if (handle == nullptr) return 1;
    out.open(argv[3], ios::binary);
    pcap_loop(handle, 0, packet_handler, nullptr);
    out.close();
    pcap_close(handle);
    return 0;
}
EOF

    git add Makefile extractor.cpp
    git commit -m "Initial commit"
    git tag v1.0-stable

    make
    cp pcap-extractor /opt/pcap-extractor-oracle
    strip /opt/pcap-extractor-oracle
    make clean

    for i in $(seq 1 142); do
        echo "// Dummy $i" >> extractor.cpp
        git commit -am "Dummy commit $i"
    done

    sed -i 's/i < payload_length;/i < payload_length - 1;/g' extractor.cpp
    git commit -am "Refactor payload loop"

    for i in $(seq 144 199); do
        echo "// Dummy $i" >> extractor.cpp
        git commit -am "Dummy commit $i"
    done

    sed -i 's/LDFLAGS=-lpcap/LDFLAGS=/g' Makefile
    git commit -am "Update Makefile"

    python3 -c '
from scapy.all import Ether, IP, UDP, wrpcap
pkts = [Ether()/IP(dst="1.2.3.4")/UDP(dport=8080)/b"Hello"]
wrpcap("/home/user/test_traffic.pcap", pkts)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
