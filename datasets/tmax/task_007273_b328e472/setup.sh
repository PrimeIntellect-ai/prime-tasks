#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip socat curl
    pip3 install pytest

    # Create user and directories
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/deploy
    mkdir -p /home/user/app_data

    # Set up the dummy server to start when the container environment is loaded
    cat << 'EOF' > /.singularity.d/env/99-start-server.sh
#!/bin/bash
if [ ! -f /tmp/dummy_server.pid ]; then
    python3 -c "
import http.server
import socketserver
class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'PONG')
httpd = socketserver.TCPServer(('127.0.0.1', 9999), Handler)
httpd.serve_forever()
" &
    echo $! > /tmp/dummy_server.pid
fi
EOF
    chmod +x /.singularity.d/env/99-start-server.sh

    chmod -R 777 /home/user
