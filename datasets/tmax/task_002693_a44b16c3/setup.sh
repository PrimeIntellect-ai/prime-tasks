#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app
    mkdir -p /home/user/corpus/clean
    mkdir -p /home/user/corpus/evil

    cat << 'EOF' > /home/user/app/mock_listener.py
import http.server
import socketserver
import json

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok"}).encode())
        else:
            self.send_response(404)
            self.end_headers()

with socketserver.TCPServer(("127.0.0.1", 9000), Handler) as httpd:
    httpd.serve_forever()
EOF

    cat << 'EOF' > /home/user/app/start.sh
#!/bin/bash
python3 /home/user/app/mock_listener.py &
nginx -c /home/user/app/nginx.conf
sleep infinity
EOF
    chmod +x /home/user/app/start.sh

    cat << 'EOF' > /home/user/app/nginx.conf
events {}
http {
    server {
        listen 8080;
        location /api/ {
            return 404;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/corpus/clean/clean1.json
{
  "nodes": ["A", "B", "C"],
  "edges": [
    {"from": "A", "to": "B"},
    {"from": "B", "to": "C"}
  ],
  "metadata": {
    "source": "api_v1",
    "priority": 5
  }
}
EOF

    cat << 'EOF' > /home/user/corpus/evil/evil1_cycle.json
{
  "nodes": ["A", "B", "C"],
  "edges": [
    {"from": "A", "to": "B"},
    {"from": "B", "to": "C"},
    {"from": "C", "to": "A"}
  ],
  "metadata": {
    "source": "api_v1",
    "priority": 5
  }
}
EOF

    cat << 'EOF' > /home/user/corpus/evil/evil2_inject.json
{
  "nodes": ["A", "B"],
  "edges": [
    {"from": "A", "to": "B"}
  ],
  "metadata": {
    "$where": "sleep(10)"
  }
}
EOF

    cat << 'EOF' > /home/user/corpus/evil/evil3_nested_inject.json
{
  "nodes": ["A", "B"],
  "edges": [
    {"from": "A", "to": "B"}
  ],
  "metadata": {
    "filter": {
      "$gt": 5
    }
  }
}
EOF

    chmod -R 777 /home/user
