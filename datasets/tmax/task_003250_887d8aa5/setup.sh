#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils curl
pip3 install pytest flask requests

mkdir -p /app

cat << 'EOF' > /app/access.log
192.168.1.5 - - [10/Oct/2023:13:55:36 -0000] "GET /login?next=/profile HTTP/1.1" 302 -
198.51.100.42 - - [10/Oct/2023:14:12:01 -0000] "GET /login?next=http://malicious-site.net/phish HTTP/1.1" 302 -
198.51.100.42 - - [10/Oct/2023:14:13:45 -0000] "POST /upload HTTP/1.1" 200 -
EOF

cat << 'EOF' > /tmp/suspicious.c
#include <stdio.h>
const char* key = "KEY-8f4a3b2c1d9e8f7a6b5c4d3e2f1a0b9c";
int main() {
    printf("Nothing to see here.\n");
    return 0;
}
EOF
gcc /tmp/suspicious.c -o /app/suspicious_bin
rm /tmp/suspicious.c

cat << 'EOF' > /app/frontend.py
from flask import Flask, request, redirect
import requests

app = Flask(__name__)

@app.route('/login')
def login():
    # Vulnerable open redirect
    next_url = request.args.get('next')
    if next_url:
        return redirect(next_url)
    return redirect('/home')

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

cat << 'EOF' > /app/backend.py
import http.server
import socketserver

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"Backend OK")

with socketserver.TCPServer(("127.0.0.1", 8081), Handler) as httpd:
    httpd.serve_forever()
EOF

cat << 'EOF' > /app/start.sh
#!/bin/bash
python3 /app/backend.py &
python3 /app/frontend.py &
sleep 2
EOF
chmod +x /app/start.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
