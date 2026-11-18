#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git binutils tcpdump
    pip3 install pytest scapy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incident
    cd /home/user/incident

    # Generate the pcap file using scapy
    cat << 'EOF' > gen_pcap.py
from scapy.all import *
pkt = IP(dst="10.0.0.1")/TCP(dport=80)/Raw(load="GET /api/v1/status HTTP/1.1\r\nHost: internal.svc\r\nAuthorization: Bearer sec_k93jD82hf8z\r\n\r\n")
wrpcap('traffic.pcap', [pkt])
EOF
    python3 gen_pcap.py
    rm gen_pcap.py

    # Create the initial validate.sh
    cat << 'EOF' > validate.sh
#!/bin/bash

source /home/user/incident/.env

if [ -z "$API_TOKEN" ]; then
    echo "Error: API_TOKEN not set"
    exit 1
fi

# Intermediate calculation
val1=10
val2=5
sum=$((val1 + val2))

# Intermediate validation assertion
if [ "$sum" -ne 15 ]; then
    echo "Assertion failed: sum is not 15"
    exit 1
fi

echo "Pipeline executed successfully with token $API_TOKEN" > /home/user/incident/success.log
EOF
    chmod +x validate.sh

    # Initialize Git repository and commit the working version
    git config --global user.email "admin@internal.svc"
    git config --global user.name "Admin"
    git config --global init.defaultBranch main
    git init
    git add validate.sh
    git commit -m "Initial working validation script"

    # Introduce the bug and commit
    sed -i 's/val2=5/val2=0/' validate.sh
    git commit -am "Update calculation logic"

    # Set permissions
    chmod -R 777 /home/user
