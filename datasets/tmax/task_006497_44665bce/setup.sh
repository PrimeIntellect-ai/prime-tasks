#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    mkdir -p /home/user/malware_analysis
    cd /home/user/malware_analysis

    git init
    git config user.email "hacker@evil.com"
    git config user.name "Hacker"

    # Commit 1: The accident
    echo "SUPER_SECRET_KEY_9921" > secret.key
    git add secret.key
    git commit -m "Initial commit with config"

    # Commit 2: Scrubbing the key and adding the code
    rm secret.key

    cat << 'EOF' > analyzer.py
import sys
import requests

def decrypt(payload_bytes, key):
    return bytes([b ^ ord(key[i % len(key)]) for i, b in enumerate(payload_bytes)])

def main():
    if len(sys.argv) != 2:
        print("Usage: python analyzer.py <secret_key>")
        sys.exit(1)
    key = sys.argv[1]

    # parse manifest
    with open('file_manifest.txt', 'r') as f:
        for line in f:
            line = line.strip()
            if not line: continue

            # BUG: Threat actor used .split(' ') which breaks on filenames with spaces.
            # Fix should be something like .rsplit(' ', 1)
            parts = line.split(' ')
            filename = parts[0]
            fhash = parts[1]

            assert len(fhash) == 32, f"Invalid hash length: {fhash} for file {filename}"

    with open('payload.enc', 'rb') as f:
        data = f.read()

    dec = decrypt(data, key)
    with open('/home/user/decrypted_flag.txt', 'w') as out:
        out.write(dec.decode('utf-8'))
    print("Payload decrypted and saved.")

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > file_manifest.txt
/bin/bash d41d8cd98f00b204e9800998ecf8427e
/etc/hosts 1234567890abcdef1234567890abcdef
/tmp/hidden space file.sh 9e107d9d372bb6826bd81d3542a419d6
/var/log/syslog 8d41402abc4b2a76b9719d911017c592
EOF

    cat << 'EOF' > requirements.txt
requests==2.28.1
urllib3==1.20
EOF

    python3 -c "
key = 'SUPER_SECRET_KEY_9921'
pt = b'FLAG{malware_analyzed_successfully_8842}'
ct = bytes([b ^ ord(key[i % len(key)]) for i, b in enumerate(pt)])
with open('payload.enc', 'wb') as f:
    f.write(ct)
"

    git add analyzer.py file_manifest.txt requirements.txt payload.enc
    git commit -m "Add main code and remove secret"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
