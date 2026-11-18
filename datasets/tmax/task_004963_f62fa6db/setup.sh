#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scapy

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > /home/user/sensor_analyzer.py
import sys
import math
import struct
import logging

logging.getLogger("scapy.runtime").setLevel(logging.ERROR)
from scapy.all import rdpcap, UDP

def analyze_pcap(pcap_file):
    packets = rdpcap(pcap_file)
    sum_val = 0.0
    sum_sq = 0.0
    count = 0

    for pkt in packets:
        if UDP in pkt and pkt[UDP].dport == 9999:
            payload = bytes(pkt[UDP].payload)
            if len(payload) >= 4:
                # Bug 1: parses as unsigned instead of signed
                val = struct.unpack('>I', payload[:4])[0]
                sum_val += val
                sum_sq += val * val
                count += 1

    if count == 0:
        return 0.0

    mean = sum_val / count
    # Bug 2: naive variance formula subject to catastrophic cancellation
    variance = (sum_sq / count) - (mean * mean)

    stddev = math.sqrt(variance)
    return stddev

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python sensor_analyzer.py <pcap_file>")
        sys.exit(1)

    stddev = analyze_pcap(sys.argv[1])
    print(f"StdDev: {stddev:.6f}")
EOF

    cat << 'EOF' > /home/user/generate_fuzz.py
import random
import struct
from scapy.all import IP, UDP, Ether
from scapy.utils import PcapWriter

with PcapWriter("/home/user/fuzz.pcap", append=False, sync=True) as pcap:
    # Generate large values close to each other to trigger cancellation
    base = random.randint(1000000000, 2000000000)
    if random.choice([True, False]):
        base = -base # Also test negative values
    for _ in range(100):
        val = base + random.randint(0, 5)
        pkt = Ether()/IP(dst="127.0.0.1")/UDP(dport=9999, sport=1234)/struct.pack(">i", val)
        pcap.write(pkt)
EOF

    cat << 'EOF' > /home/user/fuzz.sh
#!/bin/bash
for i in {1..20}; do
  python3 /home/user/generate_fuzz.py
  python3 /home/user/sensor_analyzer.py /home/user/fuzz.pcap > /dev/null
  if [ $? -ne 0 ]; then
    echo "Fuzz test failed on iteration $i"
    exit 1
  fi
done
echo "Fuzz test passed!"
EOF
    chmod +x /home/user/fuzz.sh

    # Generate the target test.pcap
    python3 -c '
import struct
from scapy.all import IP, UDP, Ether
from scapy.utils import PcapWriter

values = [-1000000000, -1000000001, -1000000002]
with PcapWriter("/home/user/test.pcap", append=False, sync=True) as pcap:
    for v in values:
        pkt = Ether()/IP(dst="127.0.0.1")/UDP(dport=9999, sport=1234)/struct.pack(">i", v)
        pcap.write(pkt)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
