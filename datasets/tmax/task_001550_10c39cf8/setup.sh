#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk time curl
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /home/user/observability/logs
    mkdir -p /home/user/observability/metrics

    # Create log_generator.py
    cat << 'EOF' > /home/user/observability/log_generator.py
import time
import random

def generate_log():
    status = random.choices([200, 301, 404, 500], weights=[0.8, 0.05, 0.1, 0.05])[0]
    bytes_sent = random.randint(100, 5000) if status != 301 else 0
    return f'127.0.0.1 - - [10/Oct/2000:13:55:36 -0700] "GET / HTTP/1.1" {status} {bytes_sent}\n'

if __name__ == "__main__":
    while True:
        with open("/home/user/observability/logs/access.log", "a") as f:
            for _ in range(10):
                f.write(generate_log())
        time.sleep(1)
EOF

    # Create dashboard_server.py
    cat << 'EOF' > /home/user/observability/dashboard_server.py
from http.server import HTTPServer, SimpleHTTPRequestHandler
import os

class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "application/json")
        self.end_headers()
        try:
            with open("/home/user/observability/metrics/summary.json", "rb") as f:
                self.wfile.write(f.read())
        except Exception:
            self.wfile.write(b"{}")

if __name__ == "__main__":
    HTTPServer(("", 8080), Handler).serve_forever()
EOF

    # Create scheduler.sh
    cat << 'EOF' > /home/user/observability/scheduler.sh
#!/bin/bash
while true; do
    cd /tmp
    env -i PWD=/tmp bash /home/user/observability/collector.sh
    sleep 5
done
EOF

    # Create the buggy collector.sh
    cat << 'EOF' > /home/user/observability/collector.sh
#!/bin/bash

# Bug 1: Relies on relative paths and environment variables
LOG_FILE="${LOG_DIR:-logs}/access.log"
OUT_FILE="${METRICS_DIR:-metrics}/summary.json"

s2=0
s3=0
s4=0
s5=0
tb=0

# Bug 2: Naive, extremely slow while-read loop
if [ -f "$LOG_FILE" ]; then
    while read -r line; do
        status=$(echo "$line" | awk '{print $9}')
        bytes=$(echo "$line" | awk '{print $10}')

        if [ "$bytes" != "-" ]; then
            tb=$((tb + bytes))
        fi

        if [ "$status" -ge 200 ] && [ "$status" -lt 300 ]; then s2=$((s2 + 1)); fi
        if [ "$status" -ge 300 ] && [ "$status" -lt 400 ]; then s3=$((s3 + 1)); fi
        if [ "$status" -ge 400 ] && [ "$status" -lt 500 ]; then s4=$((s4 + 1)); fi
        if [ "$status" -ge 500 ] && [ "$status" -lt 600 ]; then s5=$((s5 + 1)); fi
    done < "$LOG_FILE"
fi

# Ensure output directory exists (might fail if relative)
mkdir -p "$(dirname "$OUT_FILE")" 2>/dev/null || true

cat <<JSON > "$OUT_FILE"
{
  "status_2xx": $s2,
  "status_3xx": $s3,
  "status_4xx": $s4,
  "status_5xx": $s5,
  "total_bytes": $tb
}
JSON
EOF

    # Make scripts executable
    chmod +x /home/user/observability/scheduler.sh
    chmod +x /home/user/observability/collector.sh

    # Set permissions
    chmod -R 777 /home/user
