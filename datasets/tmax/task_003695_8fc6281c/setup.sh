#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_configs.py
import os
import codecs

os.makedirs('/home/user/configs', exist_ok=True)

configs = [
    ("2023-10-01", "utf8", "SRV01", 100),
    ("2023-10-02", "iso88591", "SRV01", 100),
    ("2023-10-03", "utf16le", "APP42", 100),
    ("2023-10-04", "utf8", "DB00", 100), # Invalid server name constraint: only 2 letters
    ("2023-10-05", "iso88591", "SRV01", 100),
    ("2023-10-06", "utf16le", "INVALID99", 5000), # Spike, but invalid server name constraint (skip)
    ("2023-10-07", "utf8", "SRV02", 100),
    ("2023-10-08", "iso88591", "WEB99", 2500), # Valid server name, anomalous value -> REAL CHANGEPOINT
    ("2023-10-09", "utf8", "WEB99", 2500),
]

for date, enc, srv, conn in configs:
    filename = f"/home/user/configs/config_{date}.{enc}"
    content = f"ServerName: {srv}\nMaxConnections: {conn}\nOtherConfig: xyz\n"

    if enc == "utf8":
        with open(filename, "w", encoding="utf-8") as f:
            f.write(content)
    elif enc == "iso88591":
        with open(filename, "w", encoding="iso-8859-1") as f:
            f.write(content)
    elif enc == "utf16le":
        with open(filename, "w", encoding="utf-16le") as f:
            f.write(content)
EOF

    python3 /tmp/setup_configs.py

    chmod -R 777 /home/user
