#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tzdata
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/bin /home/user/scripts /home/user/network_logs

    cat << 'EOF' > /home/user/bin/netcheck
#!/bin/bash
echo "OK - Latency 14ms"
EOF
    chmod +x /home/user/bin/netcheck

    cat << 'EOF' > /home/user/scripts/monitor.py
import subprocess
import datetime

# Bug 1: Relies on PATH
try:
    result = subprocess.run(["netcheck"], capture_output=True, text=True, check=True)
    status = result.stdout.strip()
except Exception as e:
    status = f"ERROR: {e}"

# Bug 2: UTC time, not timezone aware to America/New_York
now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

# Bug 3: Relative path, writes to cron's cwd (usually ~) instead of absolute path
with open("status.log", "a") as f:
    f.write(f"[{now}] STATUS: {status}\n")
EOF

    chmod -R 777 /home/user
