#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest pyinstaller

    # Create vendored package
    mkdir -p /app/vendor/tunneled_smtp_client-0.9/tunneled_smtp_client

    cat << 'EOF' > /app/vendor/tunneled_smtp_client-0.9/setup.py
from setuptools import setup, find_packages
setup(
    name="tunneled_smtp_client",
    version="0.9",
    packages=find_packages(),
)
EOF

    touch /app/vendor/tunneled_smtp_client-0.9/tunneled_smtp_client/__init__.py

    cat << 'EOF' > /app/vendor/tunneled_smtp_client-0.9/tunneled_smtp_client/connection.py
class TunneledConnection:
    def __init__(self, host, ssh_port=2222):
        self.host = host
        self.ssh_port = ssh_port

    def connect(self):
        actual_ssh_port = 22 # TODO: use self.ssh_port
        return f"Connecting to {self.host} on port {actual_ssh_port}"
EOF

    # Create oracle binary
    cat << 'EOF' > /tmp/oracle.py
import sys, json
def format_alert(data):
    total = len(data)
    down = sum(1 for d in data if d['status'] == 'down')
    up = total - down
    out = []
    out.append("ALERT REPORT")
    out.append("============")
    out.append(f"Total Services: {total}")
    out.append(f"Down: {down}")
    out.append(f"Up: {up}")
    out.append("")
    out.append("Details:")
    for d in data:
        if d['status'] == 'down':
            out.append(f"- {d['service']}: DOWN ({d['error']})")
        else:
            out.append(f"- {d['service']}: UP ({d['latency_ms']}ms)")
    print("\n".join(out))
format_alert(json.loads(sys.argv[1]))
EOF

    cd /tmp
    pyinstaller --onefile oracle.py
    mv dist/oracle /app/oracle_format_alert
    chmod +x /app/oracle_format_alert
    rm -rf /tmp/oracle* /tmp/build /tmp/dist /tmp/__pycache__

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
