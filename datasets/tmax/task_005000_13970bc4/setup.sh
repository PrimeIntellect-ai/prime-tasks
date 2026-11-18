#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/uptime_app

    cat << 'EOF' > /home/user/uptime_app/container_app.log
2023-10-01 10:00:01 INFO: Service started successfully.
2023-10-01 10:05:22 WARN: High latency detected on endpoint /api/v1/health.
2023-10-01 10:10:00 INFO: Routine garbage collection complete.
2023-10-01 10:15:45 INFO: Request served in 45ms.
EOF

    cat << 'EOF' > /home/user/uptime_app/uptime_monitor.py
import sys

def parse_logs(log_lines):
    # Off-by-one boundary condition error
    for i in range(len(log_lines) + 1):
        line = log_lines[i]
        if "CRITICAL" in line:
            return True
    return False

if __name__ == "__main__":
    log_path = "/home/user/uptime_app/container_app.log"
    with open(log_path, "r") as f:
        lines = f.readlines()

    if parse_logs(lines):
        print("STATUS: CRITICAL_ALERT")
        sys.exit(2)
    else:
        print("STATUS: OK")
        sys.exit(0)
EOF

    cat << 'EOF' > /home/user/uptime_app/build.sh
#!/bin/bash

# Simulated build and test runner
python3 /home/user/uptime_app/uptime_monitor.py > /home/user/uptime_app/build_success.out 2> /home/user/uptime_app/error.log
RET=$?

if [ $RET -eq 0 ] || [ $RET -eq 2 ]; then
    echo "Build Passed"
    exit 0
else
    echo "Build Failed with exit code $RET. Check error.log for stack trace."
    exit 1
fi
EOF

    chmod +x /home/user/uptime_app/build.sh

    chmod -R 777 /home/user
