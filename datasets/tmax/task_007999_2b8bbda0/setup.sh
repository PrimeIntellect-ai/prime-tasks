#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest pyjwt cryptography

    mkdir -p /home/user/app /home/user/logs /home/user/keys

    openssl genpkey -algorithm RSA -out /home/user/keys/private.pem -pkeyopt rsa_keygen_bits:2048
    openssl rsa -pubout -in /home/user/keys/private.pem -out /home/user/keys/public.pem
    chmod 600 /home/user/keys/private.pem

    cat << 'EOF' > /home/user/app/server.py
import sqlite3
from http.server import BaseHTTPRequestHandler, HTTPServer
import urllib.parse

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed_path = urllib.parse.urlparse(self.path)
        if parsed_path.path == '/api/users':
            query_params = urllib.parse.parse_qs(parsed_path.query)
            username = query_params.get('username', [''])[0]

            conn = sqlite3.connect(':memory:')
            cursor = conn.cursor()
            cursor.execute("CREATE TABLE users (id INTEGER, username TEXT, role TEXT)")
            cursor.execute("INSERT INTO users VALUES (1, 'admin', 'superuser')")
            cursor.execute("INSERT INTO users VALUES (2, 'alice', 'user')")

            # VULNERABLE SQL QUERY
            query = f"SELECT * FROM users WHERE username = '{username}'"
            try:
                cursor.execute(query)
                results = cursor.fetchall()
                self.send_response(200)
                self.end_headers()
                self.wfile.write(str(results).encode())
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(b"Error")
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('localhost', 8080), RequestHandler)
    server.serve_forever()
EOF

    cat << 'EOF' > /tmp/gen_logs.py
import jwt
import datetime

with open('/home/user/keys/private.pem', 'rb') as f:
    private_key = f.read()

# Attacker 1 - Valid JWT, SQLi, 200 OK
token1 = jwt.encode({"client_id": "malicious_client_99", "exp": datetime.datetime.utcnow() + datetime.timedelta(days=1)}, private_key, algorithm="RS256")

# Attacker 2 - Invalid JWT (wrong signature/expired), SQLi, 200 OK
token2 = jwt.encode({"client_id": "bad_client_00", "exp": datetime.datetime.utcnow() - datetime.timedelta(days=1)}, private_key, algorithm="RS256")

# Normal User - Valid JWT, normal request, 200 OK
token3 = jwt.encode({"client_id": "good_client_01", "exp": datetime.datetime.utcnow() + datetime.timedelta(days=1)}, private_key, algorithm="RS256")

# Attacker 3 - Valid JWT, SQLi, 500 Error (failed exploit)
token4 = jwt.encode({"client_id": "malicious_client_88", "exp": datetime.datetime.utcnow() + datetime.timedelta(days=1)}, private_key, algorithm="RS256")

log_content = f"""192.168.1.105 - - [10/Oct/2023:13:55:36 -0700] "GET /api/users?username=admin' OR 1=1 -- HTTP/1.1" 200 152 "Authorization: Bearer {token1}"
10.0.0.52 - - [10/Oct/2023:14:02:11 -0700] "GET /api/users?username=admin' UNION SELECT * FROM users -- HTTP/1.1" 200 152 "Authorization: Bearer {token2}"
172.16.0.4 - - [10/Oct/2023:14:15:00 -0700] "GET /api/users?username=alice HTTP/1.1" 200 45 "Authorization: Bearer {token3}"
192.168.1.200 - - [10/Oct/2023:14:22:10 -0700] "GET /api/users?username=admin' AND (SELECT 1 FROM non_existent) -- HTTP/1.1" 500 23 "Authorization: Bearer {token4}"
"""
with open('/home/user/logs/access.log', 'w') as f:
    f.write(log_content)
EOF

    python3 /tmp/gen_logs.py
    rm /tmp/gen_logs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
