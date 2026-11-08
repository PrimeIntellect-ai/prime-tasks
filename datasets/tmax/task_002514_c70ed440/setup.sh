#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssh-client openssl
    pip3 install pytest

    mkdir -p /home/user/.ssh

    # Create payload
    echo "CRITICAL_VULN_FOUND:CVE-2023-12345" | base64 > /home/user/payload.b64

    # Create scanner.sh
    cat << 'EOF' > /home/user/scanner.sh
#!/bin/bash
echo "Scanning initiated with token: $SCANNER_TOKEN"
EOF
    chmod +x /home/user/scanner.sh

    # Create the insecure python script
    cat << 'EOF' > /home/user/audit_runner.py
import subprocess
import argparse
import sys

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--token", required=True)
    args = parser.parse_args()

    # Insecure: passing token via CLI arguments
    result = subprocess.run(
        ["/home/user/scanner.sh", args.token],
        capture_output=True,
        text=True
    )

    with open("/home/user/audit_log.txt", "w") as f:
        f.write(result.stdout)

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
