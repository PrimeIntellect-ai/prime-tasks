#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make libc-dev zlib1g-dev tar gzip file
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /tmp/setup.py
import gzip

chapters = {
    "getting_started.txt": "Welcome to the system.\nIt is very easy to use.\n\xa9 2023 Corporation.\n",
    "advanced_config.txt": "Advanced settings:\n- Set proxy to 127.0.0.1\n- \xbfQue pasa?\n",
    "troubleshooting.txt": "If it breaks, try turning it off and on.\nError \xe6 is fatal.\n"
}

with gzip.open("/home/user/legacy_manual.gz", "wb") as f:
    for filename, content in chapters.items():
        delimiter = f"==== DOC_START: {filename} ====\n"
        f.write(delimiter.encode("ISO-8859-1"))
        f.write(content.encode("ISO-8859-1"))
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
