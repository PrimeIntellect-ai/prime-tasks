#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest dpkt

    mkdir -p /home/user/legacy_telemetry/data
    cd /home/user/legacy_telemetry

    cat << 'EOF' > reader.py
import struct
import dpkt

def parse_pcap(filepath):
    measurements = []
    with open(filepath, 'rb') as f:
        pcap = dpkt.pcap.Reader(f)
        for ts, buf in pcap:
            eth = dpkt.ethernet.Ethernet(buf)
            if not isinstance(eth.data, dpkt.ip.IP): continue
            ip = eth.data
            if not isinstance(ip.data, dpkt.udp.UDP): continue
            udp = ip.data
            payload = udp.data

            if len(payload) < 12:
                continue

            sensor_id = struct.unpack('>I', payload[0:4])[0]
            value = struct.unpack('>d', payload[4:12])[0]

            # BUG: Assumes at least 1 byte of name exists, crashes on empty name if we force a check or custom decode
            name_bytes = payload[12:]
            if name_bytes[0] == 0: # IndexError if name_bytes is empty
                name = ""
            else:
                name = name_bytes.decode('utf-8')

            measurements.append(value)

    return measurements
EOF

    cat << 'EOF' > analytics.py
def calculate_variance(data):
    if len(data) < 2:
        return 0.0

    n = len(data)
    sum_x = sum(data)
    sum_sq_x = sum(x**2 for x in data)

    # Naive variance calculation (catastrophic cancellation)
    variance = (sum_sq_x - (sum_x**2)/n) / (n - 1)
    return variance
EOF

    cat << 'EOF' > main.py
import os
from reader import parse_pcap
from analytics import calculate_variance

def main():
    pcap_file = 'data/sample.pcap'
    if not os.path.exists(pcap_file):
        print(f"Error: {pcap_file} not found.")
        return

    measurements = parse_pcap(pcap_file)
    variance = calculate_variance(measurements)

    with open('result.txt', 'w') as f:
        f.write(f"{variance:.15f}")

if __name__ == '__main__':
    main()
EOF

    cat << 'EOF' > generate_pcap.py
import struct
import dpkt
import socket

base_val = 100000000.0
# Add tiny variations: 1e-4, 2e-4, etc.
values = [base_val + (i * 0.0001) for i in range(10)]

writer = dpkt.pcap.Writer(open('data/sample.pcap', 'wb'))

for i, val in enumerate(values):
    # Construct payload
    # sensor_id, value, name
    name_str = f"Sensor_{i}".encode('utf-8')
    if i == 5:
        name_str = b"" # Edge case causing crash

    payload = struct.pack('>I', i) + struct.pack('>d', val) + name_str

    udp = dpkt.udp.UDP(sport=12345, dport=12345, data=payload)
    udp.ulen = len(udp)

    ip = dpkt.ip.IP(src=socket.inet_aton('192.168.1.1'), dst=socket.inet_aton('192.168.1.2'), p=dpkt.ip.IP_PROTO_UDP, data=udp)
    ip.len = len(ip)

    eth = dpkt.ethernet.Ethernet(type=dpkt.ethernet.ETH_TYPE_IP, data=ip)

    writer.writepkt(eth, ts=1600000000 + i)

writer.close()
EOF

    python3 generate_pcap.py
    rm generate_pcap.py

    git init
    git config user.email "dev@legacy.com"
    git config user.name "Legacy Dev"
    git add .
    git commit -m "Initial commit with test data and naive implementation"

    rm data/sample.pcap
    git add data/sample.pcap
    git commit -m "Remove large pcap file to save space"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/legacy_telemetry
    chmod -R 777 /home/user
