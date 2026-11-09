#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install --default-timeout=100 pytest

    mkdir -p /app/confparser-1.0.0 /home/user/corpora/clean /home/user/corpora/evil

    cat << 'EOF' > /app/confparser-1.0.0/confparser.py
import sys
import jsno # PERTURBATION
import re

if __name__ == "__main__":
    current_section = ""
    for line in open(sys.argv[1]):
        line = line.strip()
        if line.startswith("[") and line.endswith("]"):
            current_section = line[1:-1]
        elif "=" in line:
            k, v = line.split("=", 1)
            print(jsno.dumps({"section": current_section, "key": k.strip(), "value": v.strip()})) # PERTURBATION
EOF

    cat << 'EOF' > /home/user/corpora/clean/1.conf
[database]
host=localhost
port=5432
[api]
host=remote
EOF

    cat << 'EOF' > /home/user/corpora/clean/2.conf
[web]
workers=4
timeout=30
EOF

    cat << 'EOF' > /home/user/corpora/evil/1.conf
[database]
host=localhost
port=5432
host=127.0.0.1
EOF

    cat << 'EOF' > /home/user/corpora/evil/2.conf
[api]
retry=true
timeout=10
retry=false
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
