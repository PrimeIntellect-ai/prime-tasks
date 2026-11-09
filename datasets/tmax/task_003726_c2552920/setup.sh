#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        bubblewrap \
        tshark \
        tcpdump \
        libpcap-dev

    pip3 install pytest scapy

    mkdir -p /app

    # Create waf_evaluator.c
    cat << 'EOF' > /app/waf_evaluator.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 0;

    int sockfd = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in servaddr;
    memset(&servaddr, 0, sizeof(servaddr));
    servaddr.sin_family = AF_INET;
    servaddr.sin_port = htons(53);
    servaddr.sin_addr.s_addr = 0x08080808;
    if (connect(sockfd, (struct sockaddr *)&servaddr, sizeof(servaddr)) == 0) {
        // Network is reachable, hang
        sleep(60);
    }

    FILE *f = fopen(argv[1], "rb");
    if (!f) return 0;
    fseek(f, 0, SEEK_END);
    long fsize = ftell(f);
    fseek(f, 0, SEEK_SET);

    char *buf = malloc(fsize + 1);
    if (!buf) {
        fclose(f);
        return 0;
    }
    fread(buf, 1, fsize, f);
    buf[fsize] = 0;
    fclose(f);

    if (fsize > 512 && strstr(buf, "X-Debug-Probe: 1")) {
        int *p = NULL;
        *p = 1;
    }
    free(buf);
    return 0;
}
EOF

    gcc -O2 -s /app/waf_evaluator.c -o /app/waf_evaluator
    rm /app/waf_evaluator.c

    # Create generate_pcap.py
    cat << 'EOF' > /app/generate_pcap.py
from scapy.all import *
import hashlib
import random

packets = []
truth_hashes = []

for i in range(5000):
    is_vuln = (i < 142)
    payload = b"GET / HTTP/1.1\r\nHost: example.com\r\n"
    payload += b"X-ID: " + str(i).encode() + b"\r\n"
    if is_vuln:
        payload += b"X-Debug-Probe: 1\r\n"
        payload += b"X-Padding: " + b"A" * 500 + b"\r\n"
    else:
        payload += b"X-Padding: " + b"B" * random.randint(10, 600) + b"\r\n"
    payload += b"\r\n"

    if is_vuln:
        truth_hashes.append(hashlib.md5(payload).hexdigest())

    pkt = IP(dst="10.0.0.1", src="10.0.0.2")/TCP(dport=80, sport=random.randint(1024, 65535))/Raw(load=payload)
    packets.append(pkt)

random.shuffle(packets)
wrpcap('/app/traffic.pcap', packets)

with open('/app/ground_truth_hashes.txt', 'w') as f:
    for h in truth_hashes:
        f.write(h + '\n')
EOF

    python3 /app/generate_pcap.py
    rm /app/generate_pcap.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
