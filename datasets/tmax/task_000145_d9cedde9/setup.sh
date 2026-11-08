#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tcpdump
    pip3 install pytest scapy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/pcaps

    # Create script to generate pcaps
    cat << 'EOF' > /tmp/gen_pcaps.py
import os
from scapy.all import Ether, IP, TCP, wrpcap

os.makedirs("/home/user/pcaps", exist_ok=True)
pkts1 = [Ether()/IP()/TCP(sport=80, dport=8080)/(b"A"*100)] * 500
pkts2 = [Ether()/IP()/TCP(sport=80, dport=8080)/(b"B"*200)] * 500
pkts3 = [Ether()/IP()/TCP(sport=80, dport=8080)/(b"C"*300)] * 500

wrpcap("/home/user/pcaps/trace1.pcap", pkts1)
wrpcap("/home/user/pcaps/trace2.pcap", pkts2)
wrpcap("/home/user/pcaps/trace 3.pcap", pkts3)
EOF

    python3 /tmp/gen_pcaps.py
    rm /tmp/gen_pcaps.py

    # Create buggy script
    cat << 'EOF' > /home/user/pcap_processor.py
import glob
import threading
import subprocess
import time

total_bytes = 0

def process_pcap(filepath):
    global total_bytes
    # BUG 1: Unquoted filename breaks on 'trace 3.pcap'
    cmd = f"tcpdump -r {filepath} -e -nn"
    try:
        output = subprocess.check_output(cmd, shell=True, stderr=subprocess.DEVNULL, text=True)
        local_sum = 0
        for line in output.splitlines():
            if "length " in line:
                parts = line.split("length ")
                if len(parts) > 1:
                    length_val = int(parts[1].split(":")[0].strip())
                    local_sum += length_val

        # BUG 2: Race condition
        temp = total_bytes
        time.sleep(0.01) # Force race condition to be prominent
        temp += local_sum
        total_bytes = temp
    except Exception as e:
        pass

threads = []
for f in glob.glob("/home/user/pcaps/*.pcap"):
    t = threading.Thread(target=process_pcap, args=(f,))
    threads.append(t)
    t.start()

for t in threads:
    t.join()

with open("/home/user/result.txt", "w") as f:
    f.write(str(total_bytes))
EOF

    chmod -R 777 /home/user
