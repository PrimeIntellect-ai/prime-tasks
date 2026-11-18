#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scapy

    apt-get install -y gcc gdb tcpdump strace file xxd

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/ticket
    mkdir -p /home/user/solution
    cd /home/user/ticket

    cat << 'EOF' > parser.c
#include <string.h>
#include <stdio.h>

int extract_field(const char* input) {
    char local_buf[32];
    const char* colon = strchr(input, ':');
    if (!colon) return 0;
    colon++; // skip colon
    strcpy(local_buf, colon); // VULNERABILITY: Buffer Overflow
    printf("Field: %s\n", local_buf);
    return strlen(local_buf);
}

int parse_and_process(char *input) {
    return extract_field(input);
}
EOF

    gcc -c parser.c -o parser.o -fno-stack-protector -z execstack
    rm parser.c

    cat << 'EOF' > main.c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

extern int parse_and_process(char *input);

int main() {
    char buf[512];
    ssize_t n = read(0, buf, 511);
    if (n > 0) {
        buf[n] = '\0';
        parse_and_process(buf);
    }
    return 0;
}
EOF

    gcc main.c parser.o -o server -fno-stack-protector -z execstack

    cat << 'EOF' > generate_pcap.py
from scapy.all import *

# Define packets
# Stream 1: Valid
p1 = IP(src="192.168.1.100", dst="192.168.1.10")/TCP(sport=12345, dport=8888, flags="PA")/Raw(load=b"DATA:short_value\n")
# Stream 2: Valid
p2 = IP(src="192.168.1.101", dst="192.168.1.10")/TCP(sport=12346, dport=8888, flags="PA")/Raw(load=b"PING:pong_value\n")
# Stream 3: Malicious (Overflows 32-byte buffer)
payload = b"USER:" + b"A"*64 + b"\n"
p3 = IP(src="192.168.1.102", dst="192.168.1.10")/TCP(sport=12347, dport=8888, flags="PA")/Raw(load=payload)

wrpcap("traffic.pcap", [p1, p2, p3])
EOF

    python3 generate_pcap.py
    rm generate_pcap.py

    chmod -R 777 /home/user
