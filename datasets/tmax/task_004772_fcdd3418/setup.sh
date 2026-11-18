#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest cryptography

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/policy_checker.py
import sys, json, base64, os
from cryptography import x509
from cryptography.hazmat.backends import default_backend

def check_policy(b64_payload):
    try:
        payload = json.loads(base64.b64decode(b64_payload).decode('utf-8'))
        for b64_cert in payload.get('certs', []):
            pem_data = base64.b64decode(b64_cert)
            cert = x509.load_pem_x509_certificate(pem_data, default_backend())
            cn = cert.subject.get_attributes_for_oid(x509.oid.NameOID.COMMON_NAME)[0].value
            # Vulnerable command injection
            os.system(f"echo 'Checked cert: {cn}' > /dev/null")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        check_policy(sys.argv[1])
EOF

    chmod -R 777 /home/user
