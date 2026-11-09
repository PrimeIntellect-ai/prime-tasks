#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest dpkt

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/process.py
import dpkt
import json

def compute_metric(val):
    # Iterative method to compute square root
    x = val
    if x == 0: return 0.0
    while abs(x * x - val) > 1e-5:
        x = 0.5 * (x + val / x)
    return x

def main():
    total = 0.0
    with open('/home/user/traffic.pcap', 'rb') as f:
        pcap = dpkt.pcap.Reader(f)
        for ts, buf in pcap:
            try:
                eth = dpkt.ethernet.Ethernet(buf)
                ip = eth.data
                tcp = ip.data
                if len(tcp.data) > 0:
                    try:
                        payload = tcp.data.decode('utf-8')
                        data = json.loads(payload)
                        val = data.get('value', 0)
                    except UnicodeDecodeError:
                        # Fallback that causes a convergence bug
                        val = -1

                    metric = compute_metric(val)
                    total += metric
            except Exception:
                pass

    with open('/home/user/result.txt', 'w') as f:
        f.write(f"{total:.2f}\n")

if __name__ == '__main__':
    main()
EOF

cat << 'EOF' > /home/user/generate_pcap.py
import dpkt
import struct
import json
import time

def make_packet(payload_bytes):
    # Dummy MACs, IPs, and TCP headers
    tcp = dpkt.tcp.TCP(sport=1234, dport=80, seq=1, ack=1, flags=dpkt.tcp.TH_PUSH | dpkt.tcp.TH_ACK)
    tcp.data = payload_bytes

    ip = dpkt.ip.IP(src=b'\x0a\x00\x00\x01', dst=b'\x0a\x00\x00\x02', p=dpkt.ip.IP_PROTO_TCP)
    ip.data = tcp
    ip.len += len(tcp)

    eth = dpkt.ethernet.Ethernet(src=b'\x00\x11\x22\x33\x44\x55', dst=b'\x66\x77\x88\x99\xaa\xbb', type=dpkt.ethernet.ETH_TYPE_IP)
    eth.data = ip
    return bytes(eth)

packets = [
    make_packet(json.dumps({"value": 16}).encode('utf-8')),        # Correctly parses -> 4.0
    make_packet(json.dumps({"value": 9}).encode('utf-16le')),      # Fails utf-8 decode, causes val=-1 -> hang. If fixed -> 3.0
    make_packet(json.dumps({"value": -4}).encode('utf-8'))         # Valid UTF-8 but negative -> causes hang. If bounded -> 0.0
]

with open('/home/user/traffic.pcap', 'wb') as f:
    writer = dpkt.pcap.Writer(f)
    ts = time.time()
    for p in packets:
        writer.writepkt(p, ts)
        ts += 0.1
EOF

python3 /home/user/generate_pcap.py
rm /home/user/generate_pcap.py

chmod -R 777 /home/user
