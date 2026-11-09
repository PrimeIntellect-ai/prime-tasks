#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tshark gcc
    pip3 install pytest scapy

    useradd -m -s /bin/bash user || true
    cd /home/user

    # Create pcap file
    cat << 'EOF' > make_pcap.py
from scapy.all import *
p1 = IP(dst="127.0.0.1")/TCP(dport=8080)/Raw(load="POST /submit_tx HTTP/1.1\r\nHost: localhost\r\nContent-Length: 17\r\n\r\n{\"amount\": 10.50}")
p2 = IP(dst="127.0.0.1")/TCP(dport=8080)/Raw(load="POST /submit_tx HTTP/1.1\r\nHost: localhost\r\nContent-Length: 14\r\n\r\n{\"amount\": 15,")
p3 = IP(dst="127.0.0.1")/TCP(dport=8080)/Raw(load="POST /submit_tx HTTP/1.1\r\nHost: localhost\r\nContent-Length: 16\r\n\r\n{\"amount\": 8.00}")
wrpcap('traffic.pcap', [p1, p2, p3])
EOF
    python3 make_pcap.py
    rm make_pcap.py

    # Create process_tx.py
    cat << 'EOF' > process_tx.py
import sys
import json

def process(data):
    if not data: return
    obj = json.loads(data)
    print("Processed:", obj['amount'])

if __name__ == "__main__":
    for line in sys.stdin:
        process(line.strip())
EOF

    # Create summarize.c
    cat << 'EOF' > summarize.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    FILE *f = fopen("amounts.csv", "r");
    if(!f) return 1;
    float total = 0.0;
    float val;
    while(fscanf(f, "%f", &val) == 1) {
        total += val;
    }
    printf("%.2f\n", total);
    fclose(f);
    return 0;
}
EOF

    # Create amounts.csv
    cat << 'EOF' > amounts.csv
16777216.00
1.00
1.00
1.00
EOF

    chmod -R 777 /home/user
