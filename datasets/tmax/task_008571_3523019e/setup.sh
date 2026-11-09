#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scapy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/network_parser.py
#!/usr/bin/env python3
import sys
from scapy.all import rdpcap, TCP, IP

class SessionTracker:
    def __init__(self):
        self.sessions = {}
        self.orphan_buffer = []

    def process_pcap(self, filepath):
        packets = rdpcap(filepath)
        for pkt in packets:
            if IP in pkt and TCP in pkt:
                src = pkt[IP].src
                dst = pkt[IP].dst
                sport = pkt[TCP].sport
                dport = pkt[TCP].dport
                flags = pkt[TCP].flags

                session_id = f"{src}:{sport}-{dst}:{dport}"

                if flags == 'S': # SYN
                    self.sessions[session_id] = []
                elif flags == 'PA': # PSH, ACK
                    if session_id in self.sessions:
                        self.sessions[session_id].append(len(pkt))
                    else:
                        # Bug: Unbounded growth for specific orphaned packets
                        # A specific rare combination of flags (e.g., URG+PSH+ACK = 'UPA')
                        # causes the parser to incorrectly append to the orphan buffer indefinitely
                        # without ever cleaning it up or dropping it.
                        if 'U' in flags:
                            self.orphan_buffer.append(pkt)

        print(f"Processed {len(packets)} packets.")
        print(f"Active sessions: {len(self.sessions)}")
        print(f"Leaked buffer items: {len(self.orphan_buffer)}")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python network_parser.py <pcap_file>")
        sys.exit(1)

    tracker = SessionTracker()
    tracker.process_pcap(sys.argv[1])
EOF

    cat << 'EOF' > /home/user/generate_pcap.py
from scapy.all import IP, TCP, wrpcap

packets = []
# Generate 100 packets. Packet 73 (1-indexed) will be the trigger.
for i in range(1, 101):
    if i == 73:
        # Trigger packet: URG+PSH+ACK flags ('UPA') without a preceding SYN (orphan)
        pkt = IP(src="192.168.1.100", dst="10.0.0.5") / TCP(sport=12345, dport=80, flags="UPA") / b"MaliciousPayload"
    else:
        # Normal packets
        pkt = IP(src="192.168.1.50", dst="10.0.0.5") / TCP(sport=54321, dport=80, flags="S")
    packets.append(pkt)

wrpcap("/home/user/capture.pcap", packets)
EOF

    python3 /home/user/generate_pcap.py
    rm /home/user/generate_pcap.py

    chmod -R 777 /home/user
