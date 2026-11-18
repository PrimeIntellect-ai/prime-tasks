#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/monitor
    mkdir -p /home/user/logs
    mkdir -p /home/user/app_data/logs

    touch /home/user/app_data/logs/app.log

    cat << 'EOF' > /home/user/monitor/check_health.py
import os
import time
import sys

# Check timezone
if os.environ.get("TZ") != "UTC":
    print("FAIL: Expected TZ=UTC environment variable")
    sys.exit(1)

# Check locale
if os.environ.get("LC_ALL") != "C":
    print("FAIL: Expected LC_ALL=C environment variable")
    sys.exit(1)

# Check symlink path
log_file = "/home/user/logs/current/app.log"
if not os.path.exists(log_file):
    print(f"FAIL: Log file not found at {log_file}")
    sys.exit(1)

# If all pass, write status
with open("/home/user/monitor/status.txt", "w") as f:
    f.write("HEALTHY: ALL CHECKS PASSED\n")
print("SUCCESS: Health check passed")
EOF

    cat << 'EOF' > /home/user/monitor/run_monitor.sh
#!/bin/bash
# Wrapper script for health monitor
echo "Starting health check..."
python3 /home/user/monitor/check_health.py
EOF

    chmod +x /home/user/monitor/run_monitor.sh

    chmod -R 777 /home/user
