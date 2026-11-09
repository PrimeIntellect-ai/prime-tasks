#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip expect rustc
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/vault_cli.py
#!/usr/bin/env python3
import getpass
import sys

try:
    p = getpass.getpass("Enter deployment passphrase: ")
    if p == "deploy_2024":
        print("TOKEN=ZGVwbG95X3NlY3JldA==")
    else:
        print("ACCESS DENIED")
        sys.exit(1)
except Exception:
    sys.exit(1)
EOF
chmod +x /home/user/vault_cli.py

chmod -R 777 /home/user
