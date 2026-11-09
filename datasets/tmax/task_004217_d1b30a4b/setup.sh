#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip openssl
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/deploy_test.py
import argparse
import logging

logging.basicConfig(filename='/home/user/deploy.log', level=logging.INFO, 
                    format='%(asctime)s - %(levelname)s - %(message)s')

def deploy_credentials(url, username, password):
    # Vulnerable logging statement (CWE-532)
    logging.info(f"Connecting to {url} with user {username} and password {password}")
    print("Deployment test executed.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--user", required=True)
    parser.add_argument("--pass", dest="password", required=True)
    args = parser.parse_args()

    deploy_credentials(args.url, args.user, args.password)
EOF

cat << 'EOF' > /home/user/auth_test.py
import sys
import os
import subprocess

def test_auth(cert_path, user, password):
    if not os.path.exists(cert_path):
        print("Certificate not found.")
        return False

    # Check if cert has CN=test.local
    result = subprocess.run(['openssl', 'x509', '-noout', '-subject', '-in', cert_path], capture_output=True, text=True)
    if 'CN = test.local' not in result.stdout and 'CN=test.local' not in result.stdout:
        print("Invalid certificate Common Name.")
        return False

    if user == "security_admin" and password == "NewSecurePass2024!":
        with open('/home/user/auth_result.txt', 'w') as f:
            f.write("AUTH_FLOW_SUCCESS\n")
        return True
    return False

if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(1)
    test_auth(sys.argv[1], sys.argv[2], sys.argv[3])
EOF

chmod -R 777 /home/user
