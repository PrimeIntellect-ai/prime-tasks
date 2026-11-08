#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/device.c
#include <math.h>

double compute_sensor(double input) {
    // Requires libm
    return cos(input);
}
EOF

    cat << 'EOF' > /home/user/build.sh
#!/bin/bash
# BUG: missing math library link flag
gcc -shared -fPIC -o libdevice.so device.c
EOF
    chmod +x /home/user/build.sh

    cat << 'EOF' > /home/user/emulator.py
import ctypes
import urllib.request
import urllib.parse
import json
import os

try:
    lib = ctypes.CDLL(os.path.abspath('./libdevice.so'))
    lib.compute_sensor.argtypes = [ctypes.c_double]
    lib.compute_sensor.restype = ctypes.c_double

    result = lib.compute_sensor(0.0)

    data = json.dumps({"sensor_reading": result}).encode('utf-8')
    req = urllib.request.Request('http://localhost:8080/submit', data=data, method='POST')
    req.add_header('Content-Type', 'application/json')

    with urllib.request.urlopen(req) as response:
        print(f"Sent successfully, proxy returned: {response.status}")

except Exception as e:
    print(f"Emulator error: {e}")
EOF

    cat << 'EOF' > /home/user/ci_server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

class CIServer(BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)

        result_data = {
            "proxy_header": self.headers.get("X-Proxy-Routed", "missing"),
            "body": json.loads(body.decode('utf-8'))
        }

        with open("/home/user/ci_results.json", "w") as f:
            json.dump(result_data, f)

        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"OK")

if __name__ == "__main__":
    server = HTTPServer(('localhost', 9090), CIServer)
    print("CI Server running on port 9090")
    server.serve_forever()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
