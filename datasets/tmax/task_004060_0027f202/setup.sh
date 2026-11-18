#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tcpdump \
        netcat-openbsd \
        curl \
        jq \
        gawk

    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app/bash-uptime-monitor-v2.1

    cat << 'EOF' > /app/bash-uptime-monitor-v2.1/http_probe.sh
#!/bin/bash
target=$1
target_host=$2
# Incorrect formatting as described in the task
echo -e "GET / HTTP/1.1\nHost: target\n" | nc -w 1 $target_host 80
EOF
    chmod +x /app/bash-uptime-monitor-v2.1/http_probe.sh

    cat << 'EOF' > /app/bash-uptime-monitor-v2.1/monitor.sh
#!/bin/bash
state_file="/home/user/dashboard_state.json"
targets=("target1" "target2" "target3")

echo '{"targets": {}}' > "$state_file"

check_target() {
    local t=$1
    # Simulate check
    /app/bash-uptime-monitor-v2.1/http_probe.sh "$t" localhost > /dev/null 2>&1
    # Race condition modifying state file
    sed -i "s/\"targets\": {/\"targets\": {\"$t\": \"UP\",/" "$state_file"
}

for t in "${targets[@]}"; do
    check_target "$t" &
done
wait
EOF
    chmod +x /app/bash-uptime-monitor-v2.1/monitor.sh

    cat << 'EOF' > /app/bash-uptime-monitor-v2.1/serve.sh
#!/bin/bash
cat << 'PYEOF' > /tmp/server.py
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        token = os.environ.get('ADMIN_TOKEN')
        auth_header = self.headers.get('Authorization')
        if auth_header != f"Bearer {token}":
            self.send_response(401)
            self.end_headers()
            return

        if self.path == '/state':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            try:
                with open('/home/user/dashboard_state.json', 'rb') as f:
                    self.wfile.write(f.read())
            except Exception:
                self.wfile.write(b'{}')
        else:
            self.send_response(404)
            self.end_headers()

server = HTTPServer(('127.0.0.1', 8080), RequestHandler)
server.serve_forever()
PYEOF
python3 /tmp/server.py
EOF
    chmod +x /app/bash-uptime-monitor-v2.1/serve.sh

    echo '{"targets": {}}' > /home/user/dashboard_state.json
    touch /home/user/healthcheck_trace.pcap

    chmod -R 777 /home/user
    chmod -R 777 /app
