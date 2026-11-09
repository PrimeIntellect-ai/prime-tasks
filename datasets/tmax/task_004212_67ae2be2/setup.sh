#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest setuptools

    mkdir -p /home/user/netprofiler/netprofiler

    cat << 'EOF' > /home/user/netprofiler/setup.py
from setuptools import setup, find_packages

setup(
    name="netprofiler",
    version="0.1",
    packages=find_packages(),
    install_requires=[
        "dpktt", # BUG: intentional typo, should be dpkt
    ]
)
EOF

    cat << 'EOF' > /home/user/netprofiler/netprofiler/metrics.py
import dpkt

def calculate_mean_jitter(timestamps):
    if len(timestamps) < 3:
        return 0.0

    # BUG: Calculates average of differences instead of average of absolute differences of inter-arrival times
    # Actually just computes (T_last - T_first) related metric incorrectly
    inter_arrivals = [timestamps[i] - timestamps[i-1] for i in range(1, len(timestamps))]
    diffs = [inter_arrivals[i] - inter_arrivals[i-1] for i in range(1, len(inter_arrivals))]

    return sum(diffs) / len(diffs)

def parse_pcap(filepath):
    with open(filepath, 'rb') as f:
        pcap = dpkt.pcap.Reader(f)
        timestamps = []
        src_ips = {}
        total = 0
        for ts, buf in pcap:
            timestamps.append(ts)
            total += 1
            eth = dpkt.ethernet.Ethernet(buf)
            if isinstance(eth.data, dpkt.ip.IP):
                ip = eth.data
                src = "%d.%d.%d.%d" % tuple(ip.src)
                src_ips[src] = src_ips.get(src, 0) + 1

        top_ip = max(src_ips, key=src_ips.get) if src_ips else None
        return total, top_ip, calculate_mean_jitter(timestamps)
EOF

    cat << 'EOF' > /home/user/netprofiler/netprofiler/__init__.py
from .metrics import parse_pcap, calculate_mean_jitter
EOF

    cat << 'EOF' > /home/user/generate_pcap.py
import struct

def write_pcap(filename):
    with open(filename, 'wb') as f:
        # PCAP Global Header
        f.write(struct.pack('<IHHiIII', 0xa1b2c3d4, 2, 4, 0, 0, 65535, 1)) # 1 = LINKTYPE_ETHERNET

        # Packets info: (ts_sec, ts_usec, src_ip, dst_ip)
        packets = [
            (1, 0, b'\x0a\x00\x00\x01', b'\x0a\x00\x00\x02'), # 1.0s, 10.0.0.1
            (1, 500000, b'\x0a\x00\x00\x01', b'\x0a\x00\x00\x02'), # 1.5s, 10.0.0.1
            (2, 200000, b'\x0a\x00\x00\x02', b'\x0a\x00\x00\x01'), # 2.2s, 10.0.0.2
            (3, 0, b'\x0a\x00\x00\x01', b'\x0a\x00\x00\x02'), # 3.0s, 10.0.0.1
        ]

        for ts_sec, ts_usec, src, dst in packets:
            # Ethernet (14) + IP (20) = 34 bytes
            # Ethernet header: dst MAC (6), src MAC (6), ethertype (2) = IPv4 (0x0800)
            eth = b'\x00\x11\x22\x33\x44\x55' + b'\x66\x77\x88\x99\xaa\xbb' + b'\x08\x00'
            # IP header: Version/IHL (0x45), TOS (0), Total Len (20), ID (0), Flags/Frag (0), TTL (64), Protocol (1 - ICMP), Checksum (0), Src, Dst
            ip = b'\x45\x00\x00\x14\x00\x00\x00\x00\x40\x01\x00\x00' + src + dst
            data = eth + ip
            length = len(data)

            # Packet header: ts_sec, ts_usec, incl_len, orig_len
            f.write(struct.pack('<IIII', ts_sec, ts_usec, length, length))
            f.write(data)

write_pcap('/home/user/capture.pcap')
EOF
    python3 /home/user/generate_pcap.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/netprofiler /home/user/capture.pcap
    chmod -R 777 /home/user
