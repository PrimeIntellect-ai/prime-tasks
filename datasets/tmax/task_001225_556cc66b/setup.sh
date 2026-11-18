#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libpcap-dev gdb tcpdump tshark
    pip3 install pytest scapy

    mkdir -p /home/user/packet_project
    cd /home/user/packet_project

    cat << 'EOF' > parser.c
#include <pcap.h>
#include <stdio.h>
#include <string.h>

void process_payload(const u_char *payload, int len) {
    char buffer[50];
    // BUG: No bounds checking, causes segfault on packet 7
    memcpy(buffer, payload, len); 
    buffer[len] = '\0';
}

void packet_handler(u_char *user, const struct pcap_pkthdr *pkthdr, const u_char *packet) {
    // Simplified: assuming fixed ethernet/IP/TCP headers for the task
    int header_size = 14 + 20 + 20; 
    int payload_len = pkthdr->len - header_size;
    if (payload_len > 0) {
        process_payload(packet + header_size, payload_len);
    }
}

int main(int argc, char *argv[]) {
    char errbuf[PCAP_ERRBUF_SIZE];
    pcap_t *handle = pcap_open_offline(argv[1], errbuf);
    if (handle == NULL) return 1;
    pcap_loop(handle, 0, packet_handler, NULL);
    pcap_close(handle);
    return 0;
}
EOF

    cat << 'EOF' > Makefile
parser: parser.c
	gcc -g -o parser parser.c -lpcap

test: parser
	./test.sh
EOF

    cat << 'EOF' > test.sh
#!/bin/bash
./parser sample.pcap
if [ $? -eq 0 ]; then
    echo "Test passed"
    exit 0
else
    echo "Test failed"
    exit 1
fi
EOF
    chmod +x test.sh

    cat << 'EOF' > generate_pcap.py
from scapy.all import *

packets = []
for i in range(1, 11):
    if i == 7:
        payload = b"B" * 100
    else:
        payload = b"A" * 10
    pkt = Ether()/IP(src="192.168.1.2", dst="192.168.1.1")/TCP(sport=1234, dport=80)/Raw(load=payload)
    packets.append(pkt)

wrpcap("sample.pcap", packets)
EOF
    python3 generate_pcap.py
    rm generate_pcap.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
