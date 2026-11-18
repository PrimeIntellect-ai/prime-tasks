#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/mock_server.py
import http.server
import socketserver
import time

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"OK")
        elif self.path == '/timeout':
            time.sleep(2) # simulate timeout
            self.send_response(503)
            self.end_headers()
            self.wfile.write(b"Service Unavailable")
        else:
            self.send_response(404)
            self.end_headers()

httpd = socketserver.TCPServer(("", 8080), Handler)
httpd.serve_forever()
EOF

    cat << 'EOF' > /home/user/endpoints.txt
http://127.0.0.1:8080/health
http://127.0.0.1:8080/health
http://127.0.0.1:8080/health
http://127.0.0.1:8080/health
http://127.0.0.1:8080/health
http://127.0.0.1:8080/health
http://127.0.0.1:8080/health
http://127.0.0.1:8080/timeout
http://127.0.0.1:8080/health
http://127.0.0.1:8080/health
EOF

    cat << 'EOF' > /home/user/monitor_daemon.sh
#!/bin/bash

# Start the mock server in the background for testing purposes
if ! pgrep -f mock_server.py > /dev/null; then
    python3 /home/user/mock_server.py &
    sleep 1
fi

check_endpoint() {
    local url=$1
    curl -s --max-time 1 "$url" > /dev/null
    if [ $? -ne 0 ]; then
        echo "Failed to reach $url, retrying..." >> /home/user/monitor.log
        retry_endpoint "$url"
    else
        echo "$url is UP" >> /home/user/monitor.log
    fi
}

retry_endpoint() {
    local url=$1
    curl -s --max-time 1 "$url" > /dev/null
    if [ $? -ne 0 ]; then
        echo "Retry failed for $url, retrying again..." >> /home/user/monitor.log
        retry_endpoint "$url"
    else
        echo "$url recovered" >> /home/user/monitor.log
    fi
}

> /home/user/monitor.log
> /home/user/status.log

while read -r url; do
    [ -z "$url" ] && continue
    check_endpoint "$url"
done < /home/user/endpoints.txt

echo "MONITORING COMPLETE" >> /home/user/status.log
EOF

    chmod +x /home/user/monitor_daemon.sh
    chmod -R 777 /home/user
