#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create bash profile
    touch /home/user/.bash_profile

    # Create deploy data and logs
    mkdir -p /home/user/deploy_data/logs
    # Create old logs to simulate full disk
    dd if=/dev/zero of=/home/user/deploy_data/logs/old_log_1.txt bs=1M count=1
    dd if=/dev/zero of=/home/user/deploy_data/logs/old_log_2.txt bs=1M count=1

    # Create start_daemon.sh
    cat << 'EOF' > /home/user/start_daemon.sh
#!/bin/bash
if [ "$DEPLOY_ENVIRONMENT" != "production" ]; then
    echo "Error: DEPLOY_ENVIRONMENT must be production"
    exit 1
fi

if ls /home/user/deploy_data/logs/old_log_*.txt 1> /dev/null 2>&1; then
    echo "Error: Disk full. Please remove old logs in /home/user/deploy_data/logs/."
    exit 1
fi

python3 /home/user/server.py &
EOF
    chmod +x /home/user/start_daemon.sh

    # Create server.py
    cat << 'EOF' > /home/user/server.py
import http.server
import socketserver

PORT = 8000 # Needs to be updated from audio
TOKEN = "wrong" # Needs to be updated from audio

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/version":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            # Bug: serving v1 instead of v2
            self.wfile.write(b'{"version": "v1"}')
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == "__main__":
    with socketserver.TCPServer(("", PORT), Handler) as httpd:
        httpd.serve_forever()
EOF

    # Generate audio config
    mkdir -p /app
    espeak -w /app/config.wav "Port 80 85. Token is secret 99."

    chmod -R 777 /home/user
    chmod -R 777 /app
