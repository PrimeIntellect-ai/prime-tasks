#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip e2fsprogs
    pip3 install pytest scapy

    mkdir -p /home/user/ticket8022
    cd /home/user/ticket8022

    # 1. Create the ext4 image and the deleted config.json
    dd if=/dev/zero of=usb.img bs=1M count=10
    mkfs.ext4 -F usb.img
    # Inject the deleted config.json content directly into the image block
    echo '{"learning_rate": 0.05, "version": "1.2"}' | dd of=usb.img bs=1 seek=1048576 conv=notrunc

    # 2. Create the pcap file using scapy
    cat << 'EOF' > gen_pcap.py
from scapy.all import *
ip = IP(src="192.168.1.100", dst="192.168.1.10")
tcp = TCP(sport=80, dport=54321, flags="PA")
payload = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"sensor_data\": [12.5, 14.2, 13.8, -999.0, 15.1, 14.9]}\n"
pkt = Ether()/ip/tcp/payload
wrpcap('traffic.pcap', [pkt])
EOF
    python3 gen_pcap.py
    rm gen_pcap.py

    # 3. Create the buggy model.py
    cat << 'EOF' > model.py
import math

def optimize(data, lr):
    # Bug 1: Fails to filter negative numbers, causing math domain error or divergence
    # Fix: data = [d for d in data if d >= 0]

    # Target is to find the square root of the average of the data using Newton-Raphson
    avg = sum(data) / len(data)

    x = avg # initial guess
    for _ in range(100):
        # f(x) = x^2 - avg = 0
        # f'(x) = 2x
        # x = x - lr * (x^2 - avg) / (2x)
        if x == 0: break
        step = lr * (x**2 - avg) / (2 * x)
        x = x - step

    return x

if __name__ == "__main__":
    # TODO: Replace with data from traffic.pcap
    raw_data = [1.0, 2.0, -100.0]

    # TODO: Replace with learning rate from recovered config.json
    learning_rate = 1.0 

    # TODO: Filter raw_data to remove negative values before optimizing

    result = optimize(raw_data, learning_rate)
    print(f"Result: {result:.4f}")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
