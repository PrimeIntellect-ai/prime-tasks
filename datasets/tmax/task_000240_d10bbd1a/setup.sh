#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server build-essential
    pip3 install pytest websockets redis numpy scipy fastapi uvicorn

    mkdir -p /app/legacy

    cat << 'EOF' > /app/legacy/math_ops.py
# Legacy Python 2 math ops
def rolling_median(data, window):
    result = []
    for i in range(len(data)):
        if i < window - 1:
            result.append(0.0)
        else:
            window_data = sorted(data[i - window + 1 : i + 1])
            mid = window // 2
            if window % 2 == 0:
                result.append((window_data[mid - 1] + window_data[mid]) / 2.0)
            else:
                result.append(window_data[mid])
    return result
EOF

    cat << 'EOF' > /app/legacy/server.py
# Legacy Python 2 server
import BaseHTTPServer
import json
from math_ops import rolling_median

class Handler(BaseHTTPServer.BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)
        data = json.loads(post_data)

        result = rolling_median(data['data'], data['window'])

        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({'result': result}))

if __name__ == '__main__':
    server_address = ('', 8080)
    httpd = BaseHTTPServer.HTTPServer(server_address, Handler)
    httpd.serve_forever()
EOF

    # Wrapper to start redis-server before running pytest
    mv /usr/local/bin/pytest /usr/local/bin/pytest-original
    cat << 'EOF' > /usr/local/bin/pytest
#!/bin/bash
redis-server --daemonize yes
sleep 1
exec /usr/local/bin/pytest-original "$@"
EOF
    chmod +x /usr/local/bin/pytest

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
