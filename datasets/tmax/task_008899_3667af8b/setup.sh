#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tcpdump tshark
    pip3 install pytest scapy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/monitor.sh
#!/bin/bash
payload=$1
decoded=$(echo "$payload" | base64 -d 2>/dev/null)

if [ $decoded == "UP" ]; then
    echo "Service is UP"
else
    echo "Service is DOWN"
fi
EOF
    chmod +x /home/user/monitor.sh

    cat << 'EOF' > /tmp/gen_pcap.py
from scapy.all import *

pkts = [
    IP(dst="127.0.0.1")/TCP(dport=8080)/Raw(load="VVAK"),
    IP(dst="127.0.0.1")/TCP(dport=8080)/Raw(load="RE9XTgo="),
    IP(dst="127.0.0.1")/TCP(dport=8080)/Raw(load="VVAgQU5EIFJVTk5JTkcK")
]
wrpcap('/home/user/uptime_traffic.pcap', pkts)
EOF
    python3 /tmp/gen_pcap.py
    rm /tmp/gen_pcap.py

    chmod -R 777 /home/user
