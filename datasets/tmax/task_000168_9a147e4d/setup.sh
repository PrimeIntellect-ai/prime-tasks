#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip openssl procps
pip3 install pytest requests

useradd -m -s /bin/bash user || true

mkdir -p /home/user/incident_data
mkdir -p /home/user/scripts
mkdir -p /home/user/.server_hidden

openssl req -x509 -newkey rsa:2048 -keyout /home/user/.server_hidden/key.pem -out /home/user/.server_hidden/cert.pem -days 365 -nodes -subj "/CN=localhost"

cat << 'EOF' > /home/user/.server_hidden/server.py
import http.server
import ssl
import sys

port = int(sys.argv[1])
class SimpleHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/key.json':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"key": "secret_incident_key_99"}')
        else:
            self.send_response(404)
            self.end_headers()

httpd = http.server.HTTPServer(('localhost', port), SimpleHTTPRequestHandler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(certfile='/home/user/.server_hidden/cert.pem', keyfile='/home/user/.server_hidden/key.pem')
httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
httpd.serve_forever()
EOF

echo "encrypted_payload_alpha" > /home/user/incident_data/log_a.dat
echo "encrypted_payload_beta" > /home/user/incident_data/log_b.dat
echo "encrypted_payload_gamma" > /home/user/incident_data/log_c.dat
echo "encrypted_payload_delta" > /home/user/incident_data/log_d.dat

cat << 'EOF' > /home/user/scripts/decrypt_data.py
import os
import glob
import json
import requests

def get_key():
    # TODO: Update port and use the extracted certificate for verify
    url = "https://localhost:8400/key.json"
    response = requests.get(url)
    return response.json().get('key')

def main():
    try:
        key = get_key()
    except Exception as e:
        print(f"Failed to fetch key: {e}")
        return

    intel = {}
    for filepath in sorted(glob.glob('/home/user/incident_data/*.dat')):
        filename = os.path.basename(filepath)
        with open(filepath, 'r') as f:
            content = f.read().strip()
            # Mock decryption using the fetched key
            intel[filename] = f"{content}_decrypted_with_{key}"

    os.makedirs('/home/user/incident_report', exist_ok=True)
    with open('/home/user/incident_report/decrypted_intel.json', 'w') as f:
        json.dump(intel, f, indent=4)
    print("Decryption successful.")

if __name__ == "__main__":
    main()
EOF

echo "99999" > /home/user/.server_hidden/server.pid

chmod -R 777 /home/user

chmod 644 /home/user/incident_data/log_a.dat
chmod 600 /home/user/incident_data/log_b.dat
chmod 777 /home/user/incident_data/log_c.dat
chmod 640 /home/user/incident_data/log_d.dat

cat << 'EOF' > /.singularity.d/env/99-server.sh
#!/bin/sh
if ! pgrep -f "server.py 8427" > /dev/null; then
    nohup python3 /home/user/.server_hidden/server.py 8427 > /dev/null 2>&1 &
    sleep 0.5
    echo $! > /home/user/.server_hidden/server.pid
fi
EOF
chmod 755 /.singularity.d/env/99-server.sh
