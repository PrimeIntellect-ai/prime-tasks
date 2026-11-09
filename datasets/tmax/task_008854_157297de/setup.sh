#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip bubblewrap openssl faketime jq
pip3 install pytest

mkdir -p /home/user/certs

# Generate valid and expired certificates (using faketime to create an expired cert since OpenSSL 3 rejects -days -1)
openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 -keyout /home/user/certs/auth.key -out /home/user/certs/auth.pem -subj "/CN=auth" 2>/dev/null
faketime '2020-01-01' openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 -keyout /home/user/certs/payment.key -out /home/user/certs/payment.pem -subj "/CN=payment" 2>/dev/null
openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 -keyout /home/user/certs/api.key -out /home/user/certs/api.pem -subj "/CN=api" 2>/dev/null

# Create access log
cat << 'EOF' > /home/user/access.log
2023-10-01T10:00:00Z auth 192.168.1.10 STATUS: SUCCESS
2023-10-01T10:05:00Z payment 10.0.0.5 STATUS: SUCCESS
2023-10-01T10:10:00Z payment 10.0.0.2 STATUS: FAILED
2023-10-01T10:15:00Z payment 10.0.0.50 STATUS: SUCCESS
2023-10-01T10:18:00Z payment 10.0.0.5 STATUS: SUCCESS
2023-10-01T10:20:00Z api 192.168.1.11 STATUS: SUCCESS
EOF

# Create untrusted reporting script
cat << 'EOF' > /home/user/generate_report.py
import sys
import json
import socket

if len(sys.argv) != 3:
    sys.exit("Usage: generate_report.py <input_ips> <output_json>")

in_file = sys.argv[1]
out_file = sys.argv[2]

# Check for network isolation by attempting to create a socket and connect to an external IP
isolated = False
try:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.connect(("8.8.8.8", 80))
    s.close()
    isolated = False
except OSError:
    isolated = True

if not isolated:
    print("FATAL: Network isolation not detected! Script refuses to run for security reasons.")
    sys.exit(1)

try:
    with open(in_file, 'r') as f:
        ips = [line.strip() for line in f if line.strip()]
except Exception as e:
    sys.exit(f"Failed to read input: {e}")

report = {
    "service": "payment",
    "status": "compromised",
    "exfiltration_prevented": True,
    "unique_ips": ips
}

with open(out_file, 'w') as f:
    json.dump(report, f)

print("Report generated successfully.")
EOF
chmod +x /home/user/generate_report.py

# Create the user
useradd -m -s /bin/bash user || true

# Ensure ownership and permissions
chown -R user:user /home/user/certs /home/user/access.log /home/user/generate_report.py || true
chmod -R 777 /home/user
