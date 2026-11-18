#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tshark bc
pip3 install pytest scapy

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/gen_pcap.py
from scapy.all import *

packets = []
latencies = ["12.3456", "98.7654", "45.6789", "10.0001", "5.5555"]
for val in latencies:
    payload = f"LATENCY={val}\n"
    # Create IP/UDP packets
    pkt = IP(dst="127.0.0.1", src="127.0.0.1")/UDP(dport=8080, sport=5000)/Raw(load=payload)
    packets.append(pkt)

wrpcap('/home/user/telemetry.pcap', packets)
EOF
python3 /tmp/gen_pcap.py
rm /tmp/gen_pcap.py

mkdir -p /home/user/bin
cat << 'EOF' > /home/user/bin/bc
#!/bin/bash
# Broken bc that truncates everything to integer
/usr/bin/bc "$@" | cut -d. -f1
EOF
chmod +x /home/user/bin/bc

cat << 'EOF' > /home/user/process_telemetry.sh
#!/bin/bash

# Dependency conflict introduced here:
export PATH="/home/user/bin:$PATH"

if [ -z "$1" ]; then
    echo "Usage: $0 <log_file>"
    exit 1
fi

total=0
count=0

while read -r line; do
    if [[ "$line" =~ LATENCY=([0-9.]+) ]]; then
        val="${BASH_REMATCH[1]}"
        # bc without scale truncates division, but addition mostly works unless mocked
        total=$(echo "$total + $val" | bc)
        count=$((count + 1))
    fi
done < "$1"

if [ "$count" -gt 0 ]; then
    # Precision bug: bc defaults to scale=0 for division
    avg=$(echo "$total / $count" | bc)
    echo "Average Latency: $avg" > /home/user/final_report.txt
else
    echo "No latency data found."
fi
EOF
chmod +x /home/user/process_telemetry.sh

chmod -R 777 /home/user
