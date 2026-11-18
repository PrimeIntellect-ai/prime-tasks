#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libpcap-dev tcpdump gcc make
    pip3 install pytest scapy

    mkdir -p /home/user/app
    cd /home/user/app

    cat << 'EOF' > /home/user/app/packet_processor.c
#include <pcap.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <netinet/in.h>
#include <netinet/ip.h>
#include <netinet/udp.h>

void process_payload(const u_char *payload, int len) {
    int offset = 0;
    while(offset < len) {
        if (offset + 2 > len) break;
        uint8_t type = payload[offset];
        uint8_t tlen = payload[offset+1];

        if (offset + 2 + tlen > len) break;

        char *data = malloc(tlen + 1);
        memcpy(data, payload + offset + 2, tlen);
        data[tlen] = '\0';

        // Process data (simulated)
        if (type == 0xFF) {
            printf("Received end marker.\n");
        }

        // BUG 1: Memory leak (data is never freed)
        // BUG 2: Infinite loop if tlen == 0 because it forgets to add 2 for the header size
        offset += tlen; 
    }
}

void packet_handler(u_char *user_data, const struct pcap_pkthdr *pkthdr, const u_char *packet) {
    struct ip *ip_hdr = (struct ip *)(packet + 14); // Assuming Ethernet
    if (ip_hdr->ip_p == IPPROTO_UDP) {
        int ip_hdr_len = ip_hdr->ip_hl * 4;
        struct udphdr *udp_hdr = (struct udphdr *)((u_char *)ip_hdr + ip_hdr_len);

        int header_size = 14 + ip_hdr_len + 8; // Eth + IP + UDP
        int payload_len = pkthdr->len - header_size;
        const u_char *payload = packet + header_size;

        if (payload_len > 0) {
            process_payload(payload, payload_len);
        }
    }
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <pcap_file>\n", argv[0]);
        return 1;
    }

    char errbuf[PCAP_ERRBUF_SIZE];
    pcap_t *handle = pcap_open_offline(argv[1], errbuf);
    if (handle == NULL) {
        fprintf(stderr, "Error opening pcap file: %s\n", errbuf);
        return 1;
    }

    pcap_loop(handle, 0, packet_handler, NULL);
    pcap_close(handle);
    printf("Processing complete.\n");
    return 0;
}
EOF

    cat << 'EOF' > /home/user/app/Makefile
packet_processor: packet_processor.c
	gcc -O2 -Wall -g -o packet_processor packet_processor.c -lpcap

clean:
	rm -f packet_processor
EOF

    cat << 'EOF' > /home/user/app/generate_pcap.py
from scapy.all import *

packets = []

# Normal packets
for i in range(5):
    # type=1, len=4, payload="ABCD"
    payload = bytes([1, 4, 65, 66, 67, 68])
    pkt = Ether()/IP(src=f"10.0.0.{10+i}", dst="10.0.0.1")/UDP(sport=1234, dport=5678)/Raw(load=payload)
    packets.append(pkt)

# Malicious packet triggering loop/OOM (tlen = 0)
# This will cause offset += 0, spinning forever and malloc-ing 1 byte endlessly.
malicious_payload = bytes([2, 0]) 
malicious_pkt = Ether()/IP(src="192.168.1.42", dst="10.0.0.1")/UDP(sport=1337, dport=5678)/Raw(load=malicious_payload)
packets.append(malicious_pkt)

# More normal packets
for i in range(3):
    payload = bytes([1, 2, 69, 70])
    pkt = Ether()/IP(src=f"10.0.0.{20+i}", dst="10.0.0.1")/UDP(sport=1234, dport=5678)/Raw(load=payload)
    packets.append(pkt)

wrpcap("/home/user/app/traffic.pcap", packets)
EOF

    python3 /home/user/app/generate_pcap.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
