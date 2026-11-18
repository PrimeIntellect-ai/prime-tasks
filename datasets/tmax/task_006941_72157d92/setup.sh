#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc sleuthkit tshark e2tools

    pip3 install pytest scapy

    useradd -m -s /bin/bash user || true

    cd /home/user

    # Create the USB image and deleted file using e2tools to avoid loop mount issues
    dd if=/dev/zero of=usb.img bs=1M count=10
    mkfs.ext4 -F usb.img
    echo "SEED=0.789123456" > config.txt
    e2cp config.txt usb.img:/
    e2rm usb.img:/config.txt
    rm config.txt

    # Create the pcap with the exfiltrated payload
    cat << 'EOF' > generate_pcap.py
from scapy.all import Ether, IP, UDP, sendp, wrpcap

# Calculate payload
seed = 0.789123456
r = 3.99
x = seed
# Warmup
for _ in range(1000):
    x = r * x * (1.0 - x)

secret = b"OPERATION_MIDNIGHT_ECLIPSE"
hex_payload = ""

for byte in secret:
    x = r * x * (1.0 - x)
    key = int(x * 256.0) % 256
    cipher = byte ^ key
    hex_payload += f"{cipher:02x}"

# Create packet
pkt = Ether()/IP(dst="192.168.1.100", src="192.168.1.50")/UDP(sport=54321, dport=1337)/bytes.fromhex(hex_payload)
wrpcap('exfil.pcap', [pkt])
EOF
    python3 generate_pcap.py
    rm generate_pcap.py

    # Create the buggy decoder.c
    cat << 'EOF' > decoder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// BUG: Using float instead of double causes sequence divergence
void decode(float seed, const char* hex_payload) {
    float x = seed;
    float r = 3.99f;

    // warmup
    for(int i=0; i<1000; i++) {
        x = r * x * (1.0f - x);
    }

    // decode
    int len = strlen(hex_payload) / 2;
    unsigned char* decoded = malloc(len + 1);
    for(int i=0; i<len; i++) {
        char hex[3] = {hex_payload[i*2], hex_payload[i*2+1], 0};
        int byte = (int)strtol(hex, NULL, 16);
        x = r * x * (1.0f - x);
        int key = (int)(x * 256.0f) % 256;
        decoded[i] = byte ^ key;
    }
    decoded[len] = '\0';
    printf("%s", decoded);
    free(decoded);
}

int main(int argc, char** argv) {
    if(argc != 3) {
        printf("Usage: %s <seed> <hex_payload>\n", argv[0]);
        return 1;
    }
    float seed = atof(argv[1]);
    decode(seed, argv[2]);
    return 0;
}
EOF

    chmod -R 777 /home/user
