#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest scapy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/sla-monitor
    cd /home/user/sla-monitor
    git init
    git config --global user.email "test@example.com"
    git config --global user.name "Test User"

    cat << 'EOF' > create_pcaps.py
from scapy.all import Ether, IP, ICMP, wrpcap
import time

def make_pcap(filename, start_time, intervals):
    packets = []
    t = start_time
    for iv in intervals:
        t += iv
        pkt = Ether()/IP(dst="10.0.0.1")/ICMP()
        pkt.time = t
        packets.append(pkt)
    wrpcap(filename, packets)

# test_heartbeats.pcap: 100 packets, interval ~ 1.0s, low jitter
intervals_test = [1.0 + (i%3)*0.0001 for i in range(100)]
make_pcap('/home/user/sla-monitor/test_heartbeats.pcap', 1700000000.0, intervals_test)

# prod.pcap: 100 packets, interval ~ 1.0s, true jitter variance is exactly known
intervals_prod = [1.0] * 100
intervals_prod[50] = 1.005 # inject a small known deviation
make_pcap('/home/user/sla-monitor/prod.pcap', 1700000000.0, intervals_prod)
EOF
    python3 create_pcaps.py

    cat << 'EOF' > check_sla.py
import sys
from scapy.all import rdpcap
import statistics

def calculate_jitter(pcap_file):
    packets = rdpcap(pcap_file)
    times = [float(p.time) for p in packets]
    intervals = [times[i] - times[i-1] for i in range(1, len(times))]

    # Stable variance
    return statistics.variance(intervals)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(1)
    jitter = calculate_jitter(sys.argv[1])
    print(f"{jitter:.10f}")
    if jitter > 0.01:
        sys.exit(1) # Alarm!
EOF

    git add check_sla.py test_heartbeats.pcap prod.pcap create_pcaps.py
    git commit -m "Initial commit with stable jitter calc"

    echo "# comment 1" >> check_sla.py
    git commit -am "Update comments"
    echo "# comment 2" >> check_sla.py
    git commit -am "Update more comments"

    cat << 'EOF' > check_sla.py
import sys
from scapy.all import rdpcap

def calculate_jitter(pcap_file):
    packets = rdpcap(pcap_file)
    times = [float(p.time) for p in packets]
    intervals = [times[i] - times[i-1] for i in range(1, len(times))]

    sum_sq = sum(t**2 for t in times)
    sum_t = sum(times)
    n = len(times)
    var = (sum_sq / n) - (sum_t / n)**2
    return var

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(1)
    jitter = calculate_jitter(sys.argv[1])
    print(f"{jitter:.10f}")
    if jitter > 0.01 or jitter < 0:
        sys.exit(1) # Alarm!
EOF
    git commit -am "Optimize jitter calculation"

    echo "# comment 3" >> check_sla.py
    git commit -am "Add docs"
    echo "# comment 4" >> check_sla.py
    git commit -am "Cleanup"

    chmod -R 777 /home/user
