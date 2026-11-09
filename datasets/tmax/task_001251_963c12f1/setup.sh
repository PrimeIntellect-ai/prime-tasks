#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bubblewrap gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/uploads /home/user/system_cache

    echo "legitimate content 1" > /home/user/uploads/doc.txt
    echo "legitimate content 2" > /home/user/uploads/image.png

    cat << 'EOF' > /home/user/system_cache/sys_update.py
import urllib.request
import sys

try:
    # Attempt to access the network
    urllib.request.urlopen("http://1.1.1.1", timeout=1)
    print("CRITICAL FAILURE: Network is accessible! Exfiltrating data...")
    sys.exit(1)
except Exception:
    print("EVIDENCE_FLAG: Network isolated successfully. Executing safe local payload.")
EOF

    sha256sum /home/user/uploads/doc.txt | awk '{print $1}' > /home/user/manifest.txt
    sha256sum /home/user/uploads/image.png | awk '{print $1}' >> /home/user/manifest.txt

    chown -R user:user /home/user/
    chmod -R 777 /home/user
