#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tcpdump
    pip3 install pytest scapy

    mkdir -p "/home/user/pipeline/raw data"
    mkdir -p "/home/user/pipeline/output"

    cat << 'EOF' > /tmp/setup_pcap.py
from scapy.all import *
import json

packets = []
payloads = [
    {"v1": 0.1, "v2": 0.2},
    {"v1": 0.15, "v2": 0.15},
    {"v1": 0.7, "v2": 0.1}
]
for p in payloads:
    pkt = IP(dst="127.0.0.1")/UDP(dport=5000)/Raw(load=json.dumps(p).encode())
    packets.append(pkt)

wrpcap("/home/user/pipeline/raw data/sensor.pcap", packets)
EOF

    python3 /tmp/setup_pcap.py
    rm /tmp/setup_pcap.py

    cat << 'EOF' > /home/user/pipeline/config.env
DATA_DIR=/home/user/pipeline/raw data
OUTPUT_DIR=/home/user/pipeline/output
EOF

    cat << 'EOF' > /home/user/pipeline/run.sh
#!/bin/bash
source /home/user/pipeline/config.env

# Bug 1: Unquoted variables with spaces
for file in $(ls $DATA_DIR/*.pcap); do
    echo "Processing $file"
    python3 /home/user/pipeline/aggregate.py "$file" > $OUTPUT_DIR/results.txt
done
EOF

    cat << 'EOF' > /home/user/pipeline/aggregate.py
import sys
from scapy.all import rdpcap, UDP, Raw
import json

def process_pcap(filepath):
    packets = rdpcap(filepath)
    count = 1
    for pkt in packets:
        if UDP in pkt and pkt[UDP].dport == 5000 and Raw in pkt:
            try:
                data = json.loads(pkt[Raw].load.decode('utf-8'))
                # Bug 2: Floating point precision issue
                total = data['v1'] + data['v2']
                print(f"Packet {count}: {total}")
                count += 1
            except Exception as e:
                pass

if __name__ == "__main__":
    if len(sys.argv) > 1:
        process_pcap(sys.argv[1])
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
