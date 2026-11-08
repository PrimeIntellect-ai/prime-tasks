#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest dpkt

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/pipeline

    cat << 'EOF' > /home/user/pipeline/requirements.txt
requests==2.31.0
EOF

    cat << 'EOF' > /home/user/pipeline/build_and_run.sh
#!/bin/bash

# Install dependencies locally
pip3 install --user -r requirements.txt

# Run the pipeline
python3 process_telemetry.py
EOF
    chmod +x /home/user/pipeline/build_and_run.sh

    cat << 'EOF' > /home/user/pipeline/process_telemetry.py
import dpkt
import socket
import json
import sys

def process_pcap(file_path):
    valid_count = 0

    with open(file_path, 'rb') as f:
        pcap = dpkt.pcap.Reader(f)
        for timestamp, buf in pcap:
            eth = dpkt.ethernet.Ethernet(buf)
            if not isinstance(eth.data, dpkt.ip.IP):
                continue
            ip = eth.data
            if not isinstance(ip.data, dpkt.udp.UDP):
                continue

            udp = ip.data
            if udp.dport == 5000:
                # BUG: Assumes perfectly valid utf-8 JSON, will crash on binary/malformed payload
                payload = udp.data.decode('utf-8')
                data = json.loads(payload)
                valid_count += 1

    with open('/home/user/pipeline/summary.json', 'w') as out:
        json.dump({"valid_packets": valid_count}, out)

if __name__ == "__main__":
    process_pcap('telemetry.pcap')
EOF

    cat << 'EOF' > /tmp/generate_pcap.py
import dpkt
import socket
import struct
import time

def create_packet(src_ip, payload):
    eth = dpkt.ethernet.Ethernet(
        src=b'\x00\x11\x22\x33\x44\x55',
        dst=b'\xff\xff\xff\xff\xff\xff',
        type=dpkt.ethernet.ETH_TYPE_IP
    )
    ip = dpkt.ip.IP(
        src=socket.inet_aton(src_ip),
        dst=socket.inet_aton('192.168.1.100'),
        p=dpkt.ip.IP_PROTO_UDP
    )
    udp = dpkt.udp.UDP(
        sport=12345,
        dport=5000
    )
    udp.data = payload
    udp.ulen = len(udp)
    ip.data = udp
    ip.len = len(ip)
    eth.data = ip
    return eth.pack()

packets = [
    ('192.168.1.10', b'{"sensor": "temp", "val": 22}'),
    ('192.168.1.11', b'{"sensor": "temp", "val": 23}'),
    ('10.0.0.55', b'\xde\xad\xbe\xef\x00\x01\x02\x03\xff\xff'), # Malformed binary payload
    ('192.168.1.12', b'{"sensor": "temp", "val": 21}'),
    ('192.168.1.13', b'{"sensor": "temp", "val": 24}'),
]

with open('/home/user/pipeline/telemetry.pcap', 'wb') as f:
    writer = dpkt.pcap.Writer(f)
    ts = time.time()
    for ip, payload in packets:
        writer.writepkt(create_packet(ip, payload), ts)
        ts += 1.0
EOF

    python3 /tmp/generate_pcap.py
    rm /tmp/generate_pcap.py

    chmod -R 777 /home/user
