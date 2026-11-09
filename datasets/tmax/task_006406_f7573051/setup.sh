#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest cryptography

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incident_data
    mkdir -p /home/user/analysis

    cat << 'EOF' > /tmp/setup.py
import os
import gzip
import base64
import json
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization
import datetime

os.makedirs("/home/user/incident_data", exist_ok=True)

malware_content = b"""import subprocess
import sys

def execute_remote_instruction(target_host):
    # Execute ping to verify host is up
    command = "ping -c 4 " + target_host
    # Vulnerable to OS Command Injection
    subprocess.Popen(command, shell=True)

if __name__ == "__main__":
    execute_remote_instruction(sys.argv[1])
"""

compressed_payload = gzip.compress(malware_content)
b64_payload = base64.b64encode(compressed_payload).decode('utf-8')

with open("/home/user/incident_data/intercepted_payload.txt", "w") as f:
    f.write(b64_payload)

dns_records = {
    "google.com": "142.250.190.46",
    "evil-c2-server.internal": "192.168.100.88",
    "legitimate.internal": "192.168.1.10"
}
with open("/home/user/incident_data/local_dns.json", "w") as f:
    json.dump(dns_records, f)

private_key = rsa.generate_private_key(
    public_exponent=65537,
    key_size=2048,
)
subject = issuer = x509.Name([
    x509.NameAttribute(NameOID.COMMON_NAME, u"evil-c2-server.internal"),
])
cert = x509.CertificateBuilder().subject_name(
    subject
).issuer_name(
    issuer
).public_key(
    private_key.public_key()
).serial_number(
    x509.random_serial_number()
).not_valid_before(
    datetime.datetime.utcnow()
).not_valid_after(
    datetime.datetime.utcnow() + datetime.timedelta(days=10)
).sign(private_key, hashes.SHA256())

with open("/home/user/incident_data/c2_certificate.pem", "wb") as f:
    f.write(cert.public_bytes(serialization.Encoding.PEM))
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
