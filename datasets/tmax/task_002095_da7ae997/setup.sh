#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest scapy

useradd -m -s /bin/bash user || true
mkdir -p /home/user/ticket
cd /home/user/ticket

cat << 'EOF' > generate_setup.py
import math
import random
from scapy.all import IP, UDP, wrpcap, Ether

random.seed(42)

pcap_packets = []
log_a = open("service_a.log", "w")
log_b = open("service_b.log", "w")

# Generate normal data with mean 50, stddev 5
mean = 50
stddev = 5

class BuggyDetector:
    def __init__(self):
        self.count = 0
        self.mean = 0.0
        self.M2 = 0.0

    def process(self, value):
        self.count += 1
        delta = value - self.mean
        self.mean += delta / self.count
        # BUG 1: Should be delta * delta2 (where delta2 = value - new_mean)
        self.M2 += delta * delta 

        if self.count < 3:
            return True

        variance = self.M2 / self.count
        # BUG 2: Missing math.sqrt()
        stddev = variance 

        if abs(value - self.mean) > 3 * stddev:
            return False
        return True

detector = BuggyDetector()

timestamp = 1670000000.0
for i in range(1, 101):
    val = random.gauss(mean, stddev)
    if i == 50:
        val = 1000.0 # Intentional outlier

    payload = f"{val:.4f}".encode('utf-8')

    # Create scapy packet
    pkt = Ether()/IP(src="10.0.0.1", dst="10.0.0.2")/UDP(sport=5000, dport=5001)/payload
    pkt.time = timestamp
    pcap_packets.append(pkt)

    # Log A
    log_a.write(f"{timestamp:.3f} INFO Sent: {val:.4f}\n")

    # Log B
    accepted = detector.process(val)
    status = "ACCEPTED" if accepted else "REJECTED"
    log_b.write(f"{timestamp:.3f} INFO Received: {val:.4f} - {status}\n")

    timestamp += 0.1

wrpcap("traffic.pcap", pcap_packets)
log_a.close()
log_b.close()
EOF

python3 generate_setup.py

cat << 'EOF' > detector.py
import math

class AnomalyDetector:
    def __init__(self):
        self.count = 0
        self.mean = 0.0
        self.M2 = 0.0

    def process(self, value):
        self.count += 1
        delta = value - self.mean
        self.mean += delta / self.count

        # Calculate M2 (sum of squares of differences from the current mean)
        self.M2 += delta * delta

        if self.count < 3:
            return True

        variance = self.M2 / self.count
        stddev = variance # TODO: check if this is correct

        if abs(value - self.mean) > 3 * stddev:
            return False
        return True
EOF

cat << 'EOF' > run_pipeline.py
import json
from scapy.all import rdpcap
from detector import AnomalyDetector

def run():
    packets = rdpcap('/home/user/ticket/traffic.pcap')
    detector = AnomalyDetector()

    accepted_count = 0
    rejected_count = 0

    for pkt in packets:
        if pkt.haslayer('UDP') and pkt['UDP'].dport == 5001:
            val = float(pkt['Raw'].load.decode('utf-8'))
            if detector.process(val):
                accepted_count += 1
            else:
                rejected_count += 1

    result = {
        "accepted": accepted_count,
        "rejected": rejected_count,
        "final_mean": round(detector.mean, 4)
    }

    with open('/home/user/ticket/resolution.json', 'w') as f:
        json.dump(result, f)

if __name__ == '__main__':
    run()
EOF

chown -R user:user /home/user/ticket
chmod -R 777 /home/user
