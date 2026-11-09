#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scapy

    mkdir -p /home/user/service

    cat << 'EOF' > /home/user/service/packet_processor.py
import sys
from scapy.utils import PcapReader

class PacketStats:
    def __init__(self):
        self.history = [] # Memory leak
        self.n = 0
        self.sum_x = 0.0
        self.sum_x2 = 0.0

    def process_packet(self, pkt):
        val = len(pkt)
        self.history.append(pkt) # Stores entire packet object
        self.n += 1
        self.sum_x += val
        self.sum_x2 += val * val

    def get_variance(self):
        if self.n < 2:
            return 0.0
        # Numerically unstable naive variance
        mean = self.sum_x / self.n
        return (self.sum_x2 / self.n) - (mean * mean)

def main(pcap_file):
    stats = PacketStats()
    with PcapReader(pcap_file) as pcap_reader:
        for pkt in pcap_reader:
            stats.process_packet(pkt)
    print(f"{stats.get_variance():.4f}")

if __name__ == "__main__":
    main(sys.argv[1])
EOF

    cat << 'EOF' > /home/user/service/crash.log
Traceback (most recent call last):
  File "/home/user/service/packet_processor.py", line 33, in <module>
    main(sys.argv[1])
  File "/home/user/service/packet_processor.py", line 29, in main
    stats.process_packet(pkt)
  File "/home/user/service/packet_processor.py", line 13, in process_packet
    self.history.append(pkt)
MemoryError
EOF

    # Generating the PCAP file
    python3 -c '
from scapy.all import Ether, IP, TCP, wrpcap

pkts = []
# Create 1000 packets with lengths oscillating slightly around 1500
for i in range(1000):
    payload_size = 1400 + (i % 50)
    pkt = Ether()/IP()/TCP()/(b"X" * payload_size)
    pkts.append(pkt)

wrpcap("/home/user/service/test_traffic.pcap", pkts)
'

    python3 -c '
from scapy.utils import PcapReader
lengths = []
with PcapReader("/home/user/service/test_traffic.pcap") as pr:
    for p in pr:
        lengths.append(len(p))
mean = sum(lengths)/len(lengths)
var = sum((x - mean)**2 for x in lengths) / len(lengths)
with open("/home/user/expected_solution.txt", "w") as f:
    f.write(f"{var:.4f}\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
