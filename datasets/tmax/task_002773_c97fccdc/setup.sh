#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sudo
    pip3 install pytest scapy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_pcap.py
import sys
import subprocess
try:
    from scapy.all import IP, TCP, UDP, DNS, DNSQR, Raw, wrpcap
except ImportError:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "scapy"])
    from scapy.all import IP, TCP, UDP, DNS, DNSQR, Raw, wrpcap

pkts = [
    IP(src="10.0.0.5", dst="198.51.100.22")/TCP(sport=1024, dport=80)/Raw(b"GET /malware HTTP/1.1\r\nHost: 198.51.100.22\r\n\r\n"),
    IP(src="10.0.0.5", dst="10.0.0.8")/TCP(sport=1025, dport=443)/Raw(b"Internal traffic"),
    IP(src="10.0.0.5", dst="203.0.113.5")/UDP(sport=53, dport=53)/DNS(rd=1, qd=DNSQR(qname="malicious.com")),
    IP(src="127.0.0.1", dst="127.0.0.1")/TCP(sport=5000, dport=5000)/Raw(b"Loopback"),
]
wrpcap("/home/user/traffic.pcap", pkts)
EOF

    python3 /home/user/setup_pcap.py
    rm /home/user/setup_pcap.py

    cat << 'EOF' > /home/user/service_logs.txt
Nov  2 08:11:22 testhost systemd[1]: Started suspicious.
Oct 12 10:01:22 testhost suspicious_bin[1234]: Connection to 198.51.100.22 established.
Oct 12 10:01:25 testhost kernel: DROP SRC=203.0.113.5 DST=10.0.0.5
Oct  9 09:12:00 testhost systemd[1]: Installed suspicious_bin.
Dec  1 12:00:00 testhost network: Connection to 10.0.0.8 closed.
Sep 30 23:59:59 testhost root: Initialized system.
EOF

    cat << 'EOF' > /home/user/analyze.sh
#!/bin/bash
# Extract destination IPs from pcap
tshark -r /home/user/traffic.pcap -T fields -e ip.dst | sort | uniq > /home/user/ips.txt

# Filter logs based on IPs
grep -f /home/user/ips.txt /home/user/service_logs.txt > /home/user/matched_logs.txt

# Sort chronologically
sort /home/user/matched_logs.txt > /home/user/malware_timeline.log
EOF
    chmod +x /home/user/analyze.sh

    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    chmod -R 777 /home/user
