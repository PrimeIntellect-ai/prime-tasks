#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest scapy dpkt

mkdir -p /home/user/ticket_8992
cd /home/user/ticket_8992

# Generate a synthetic pcap file
python3 -c "
from scapy.all import Ether, IP, TCP, wrpcap
packets = []
# Normal traffic
for i in range(1, 5):
    packets.append(Ether()/IP(src=f'192.168.1.{i}', dst=f'192.168.1.{i+1}')/TCP(sport=1024, dport=80))
    packets.append(Ether()/IP(src=f'192.168.1.{i+1}', dst=f'192.168.1.{i}')/TCP(sport=80, dport=1024))

# Anomalous traffic causing the bug (Only sending, never receiving, triggering div by zero in ratio calc)
packets.append(Ether()/IP(src='10.99.99.99', dst='192.168.1.1')/TCP(sport=4444, dport=80))
packets.append(Ether()/IP(src='10.99.99.99', dst='192.168.1.2')/TCP(sport=4444, dport=80))

wrpcap('capture.pcap', packets)
"

# Create the buggy netmapper.py
cat << 'EOF' > netmapper.py
import json
import logging
import sys
from dpkt.pcap import Reader
from dpkt.ethernet import Ethernet
from dpkt.ip import IP

logging.basicConfig(filename='netmapper.log', level=logging.DEBUG)

def parse_pcap(filepath):
    nodes = {}
    with open(filepath, 'rb') as f:
        pcap = Reader(f)
        for ts, buf in pcap:
            eth = Ethernet(buf)
            if not isinstance(eth.data, IP):
                continue
            ip = eth.data
            src = '.'.join(map(str, ip.src))
            dst = '.'.join(map(str, ip.dst))

            if src not in nodes: nodes[src] = {'sent': 0, 'recv': 0, 'weight': 1.0}
            if dst not in nodes: nodes[dst] = {'sent': 0, 'recv': 0, 'weight': 1.0}

            nodes[src]['sent'] += 1
            nodes[dst]['recv'] += 1

    return nodes

def calculate_node_weights(nodes):
    # Initialize ratios
    for ip, data in nodes.items():
        # BUG 1: ZeroDivisionError if recv is 0
        ratio = data['sent'] / data['recv']
        data['ratio'] = ratio

    iteration = 0
    converged = False

    while not converged and iteration < 10000:
        iteration += 1
        max_change = 0.0

        for ip, data in nodes.items():
            old_weight = data['weight']
            # BUG 2: Logical error causing divergence/oscillation. 
            # Should be: new_weight = old_weight + 0.1 * (data['ratio'] - old_weight)
            # Buggy version oscillates because of sign error
            new_weight = old_weight - 0.5 * (data['ratio'] - old_weight) 

            change = abs(new_weight - old_weight)
            if change > max_change:
                max_change = change

            data['weight'] = new_weight

        if max_change < 0.001:
            converged = True

    if not converged:
        logging.error("Convergence failure: max iterations reached without stable weights.")
        sys.exit(1)

    print(f"Converged in {iteration} iterations")
    return nodes

if __name__ == '__main__':
    try:
        nodes = parse_pcap('capture.pcap')
        final_nodes = calculate_node_weights(nodes)
        with open('topology.json', 'w') as f:
            json.dump(final_nodes, f, indent=2)
    except Exception as e:
        logging.error("Fatal error", exc_info=True)
        sys.exit(1)
EOF

# Create initial log showing the crash
python3 netmapper.py || true

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
