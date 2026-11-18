#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/.ssh
    mkdir -p /home/user/certs

    cat << 'EOF' > /home/user/.ssh/config
Host migration-target
    HostName 192.168.1.100
    User deploy
    PubkeyAuthentication no
    PasswordAuthentication yes
EOF

    touch /home/user/.ssh/migration_key
    chmod 600 /home/user/.ssh/migration_key

    cat << 'EOF' > /home/user/services.json
{
  "web": {
    "domain": "example.com",
    "tls_cert": "/home/user/certs/web.crt"
  },
  "email": {
    "domain": "mail.example.com",
    "tls_cert": "/home/user/certs/mail.crt"
  }
}
EOF

    echo "mock_web_cert_data" > /home/user/certs/web.crt

    cat << 'EOF' > /home/user/validate_deployment.py
import json
import sys

def main():
    with open('/home/user/services.json', 'r') as f:
        services = json.load(f)

    report = {}
    for service_name, config in services.items():
        cert_path = config['tls_cert']
        # VULNERABLE CODE: No error handling
        with open(cert_path, 'r') as cert_file:
            cert_data = cert_file.read()
            report[service_name] = "OK"

    with open('/home/user/report.json', 'w') as f:
        json.dump(report, f, indent=2)

if __name__ == "__main__":
    main()
EOF

    chmod -R 777 /home/user
