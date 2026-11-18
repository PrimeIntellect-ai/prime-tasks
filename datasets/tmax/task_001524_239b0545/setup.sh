#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ make libpcap-dev
    pip3 install pytest scapy

    mkdir -p /home/user/pcap_parser
    cd /home/user/pcap_parser

    # 1. Create the expected output
    cat << 'EOF' > expected_output.txt
HELLO_AI_AGENT_DEBUGGING_DATA
EOF

    # 2. Create a python script to generate the pcap file using scapy
    cat << 'EOF' > gen_pcap.py
from scapy.all import *
payload = b"HELLO_AI_AGENT_DEBUGGING_DATA"
pkt = Ether()/IP(dst="192.168.1.100")/UDP(dport=12345, sport=54321)/Raw(load=payload)
wrpcap("capture.pcap", [pkt])
EOF
    python3 gen_pcap.py

    # 3. Create the buggy Makefile
    cat << 'EOF' > Makefile
all:
	gcc -lpcap main.cpp -o parser
EOF

    # 4. Create the buggy main.cpp
    cat << 'EOF' > main.cpp
#include <iostream>
#include <pcap.h>
#include <netinet/in.h>
#include <netinet/ip.h>
#include <netinet/udp.h>
#include <net/ethernet.h>

void packet_handler(u_char *args, const struct pcap_pkthdr *header, const u_char *packet) {
    struct ether_header *eth_header = (struct ether_header *) packet;
    if (ntohs(eth_header->ether_type) != ETHERTYPE_IP) {
        return;
    }

    const u_char *ip_header_ptr = packet + 14;
    struct ip *ip_hdr = (struct ip *) ip_header_ptr;
    int ip_header_length = ip_hdr->ip_hl * 4;

    if (ip_hdr->ip_p != IPPROTO_UDP) {
        return;
    }

    const u_char *udp_header_ptr = ip_header_ptr + ip_header_length;

    // BUG: Payload pointer is pointing to the start of the UDP header, not the payload
    // It should be: const u_char *payload = udp_header_ptr + 8;
    const u_char *payload = udp_header_ptr;

    int payload_length = header->caplen - 14 - ip_header_length - 8;

    for (int i = 0; i < payload_length; i++) {
        std::cout << payload[i];
    }
    std::cout << std::endl;
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <pcap_file>" << std::endl;
        return 1;
    }

    char errbuf[PCAP_ERRBUF_SIZE];
    pcap_t *handle = pcap_open_offline(argv[1], errbuf);
    if (handle == nullptr) {
        std::cerr << "Error opening pcap file: " << errbuf << std::endl;
        return 1;
    }

    pcap_loop(handle, 0, packet_handler, nullptr);
    pcap_close(handle);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
