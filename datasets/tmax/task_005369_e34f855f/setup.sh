#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget tar g++ make libssl-dev openssl
    pip3 install pytest

    mkdir -p /app

    # Download and vendor re2
    wget https://github.com/google/re2/archive/refs/tags/2023-03-01.tar.gz -O /tmp/re2.tar.gz
    tar -xzf /tmp/re2.tar.gz -C /tmp
    mv /tmp/re2-2023-03-01 /app/re2
    # Introduce deliberate typo in Makefile
    sed -i 's/CXXFLAGS/CXXXFLAGS/g' /app/re2/Makefile

    # Generate ground truth log
    cat << 'EOF' > /app/ground_truth.log
Jan 1 12:00:00 host app[123]: User registered with SSN 123-45-6789
Jan 1 12:05:00 host app[124]: Payment processed with CC 1234-5678-1234-5678
Jan 1 12:10:00 host app[125]: Another CC 1111222233334444 used
EOF

    # Encrypt the log to create evidence.enc
    openssl enc -aes-256-cbc -K 3132333435363738393061626364656631323334353637383930616263646566 -iv 30303030303030303030303030303030 -in /app/ground_truth.log -out /app/evidence.enc

    # Create dummy verifier script
    cat << 'EOF' > /app/verify_f1.py
#!/usr/bin/env python3
import sys

def main():
    print("Verification script")
    sys.exit(0)

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/verify_f1.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
