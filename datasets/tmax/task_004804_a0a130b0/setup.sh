#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import json

def setup_environment():
    os.makedirs("/home/user", exist_ok=True)
    xml_path = "/home/user/network_configs.xml"

    # Deterministic sequence of configs for core-router-01 and noise for other servers
    events = [
        {"ts": "2023-10-01T10:00:00Z", "srv": "core-router-01", "cfg": {"BGP_AS": 65000, "OSPF_AREA": "0.0.0.0", "MAX_ROUTES": 10000}},
        {"ts": "2023-10-01T10:05:00Z", "srv": "edge-router-02", "cfg": {"BGP_AS": 65001}},
        {"ts": "2023-10-01T11:00:00Z", "srv": "core-router-01", "cfg": {"BGP_AS": 65000, "OSPF_AREA": "0.0.0.0", "MAX_ROUTES": 15000, "NEW_FEATURE": "enabled"}},
        {"ts": "2023-10-01T11:30:00Z", "srv": "core-router-01", "cfg": {"BGP_AS": 65000, "MAX_ROUTES": 15000, "NEW_FEATURE": "disabled"}},
    ]

    # Generate a larger deterministic set to ensure chunking kicks in (> 20 diffs)
    for i in range(1, 15):
        ts = f"2023-10-02T{i:02d}:00:00Z"
        # 2 changes per iteration: MAX_ROUTES changes, plus a dynamic key added/removed
        cfg = {
            "BGP_AS": 65000,
            "MAX_ROUTES": 15000 + i * 100,
        }
        if i % 2 == 0:
            cfg[f"TEMP_ROUTE_{i}"] = "active"

        events.append({"ts": ts, "srv": "core-router-01", "cfg": cfg})
        events.append({"ts": f"2023-10-02T{i:02d}:30:00Z", "srv": "access-switch-01", "cfg": {"VLAN": 100 + i}})

    with open(xml_path, "w") as f:
        f.write("<dumps>\n")
        for ev in events:
            f.write("  <record>\n")
            f.write(f"    <timestamp>{ev['ts']}</timestamp>\n")
            f.write(f"    <server_id>{ev['srv']}</server_id>\n")
            f.write(f"    <config>{json.dumps(ev['cfg'])}</config>\n")
            f.write("  </record>\n")
        f.write("</dumps>\n")

setup_environment()
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
