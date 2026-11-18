#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest cryptography

    mkdir -p /home/user/certs /home/user/logs

    cat << 'EOF' > /tmp/setup_env.py
import os
import json
import base64
from datetime import datetime, timedelta
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization

os.makedirs('/home/user/certs', exist_ok=True)
os.makedirs('/home/user/logs', exist_ok=True)

# Generate Expired Cert for WAF-Intermediate-Node-7
private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
subject = issuer = x509.Name([
    x509.NameAttribute(NameOID.COMMON_NAME, u"WAF-Intermediate-Node-7"),
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
    datetime.utcnow() - timedelta(days=100)
).not_valid_after(
    datetime.utcnow() - timedelta(days=10) # Expired 10 days ago
).add_extension(
    x509.BasicConstraints(ca=True, path_length=None), critical=True,
).sign(private_key, hashes.SHA256())

cert_pem = cert.public_bytes(serialization.Encoding.PEM).decode('utf-8')

with open('/home/user/certs/server_chain.pem', 'w') as f:
    f.write("-----BEGIN CERTIFICATE-----\nMIID...Fake Valid Root...\n-----END CERTIFICATE-----\n")
    f.write(cert_pem)
    f.write("-----BEGIN CERTIFICATE-----\nMIID...Fake Valid Leaf...\n-----END CERTIFICATE-----\n")

# Generate API logs
header = base64.urlsafe_b64encode(b'{"alg":"none","typ":"JWT"}').decode('utf-8').rstrip('=')
payload_dict = {
    "user": "guest",
    "profile_data": "<img src=x onerror=fetch('/grant?role=SuperAdmin&user=h4x0r')>",
    "iat": 1690000000
}
payload = base64.urlsafe_b64encode(json.dumps(payload_dict).encode('utf-8')).decode('utf-8').rstrip('=')
malicious_jwt = f"{header}.{payload}."

log_content = f"""
192.168.1.10 - - [22/Jul/2023:10:00:00 +0000] "GET /api/status HTTP/1.1" 200 15 "-" "curl/7.68.0"
198.51.100.45 - - [22/Jul/2023:10:05:00 +0000] "POST /api/profile HTTP/1.1" 200 45 "-" "Mozilla/5.0" "Authorization: Bearer {malicious_jwt}"
203.0.113.20 - - [22/Jul/2023:10:06:00 +0000] "GET /api/data HTTP/1.1" 200 120 "-" "Mozilla/5.0"
"""
with open('/home/user/logs/api_traffic.log', 'w') as f:
    f.write(log_content.strip() + "\n")

# Generate Privilege Events
events = [
    {"timestamp": 1690010000, "action": "role_grant", "target_user": "alice", "role": "Editor", "granted_by": "admin"},
    {"timestamp": 1690020450, "action": "role_grant", "target_user": "h4x0r", "role": "SuperAdmin", "granted_by": "admin"},
    {"timestamp": 1690025000, "action": "role_grant", "target_user": "bob", "role": "Viewer", "granted_by": "alice"}
]
with open('/home/user/logs/privilege_events.json', 'w') as f:
    json.dump(events, f, indent=2)
EOF

    python3 /tmp/setup_env.py
    rm /tmp/setup_env.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
