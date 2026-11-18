#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        g++ \
        inotify-tools \
        curl \
        nginx \
        redis-server

    pip3 install pytest flask redis

    mkdir -p /app/bin /app/services /home/user/incoming

    # Create oracle ingestor
    cat << 'EOF' > /app/bin/oracle_ingestor.cpp
#include <iostream>
#include <vector>
#include <cstdint>

using namespace std;

int main() {
    vector<uint8_t> data;
    char c;
    while (cin.get(c)) {
        data.push_back(static_cast<uint8_t>(c));
    }

    cout << "ARTI";

    uint32_t size = data.size();
    cout.write(reinterpret_cast<const char*>(&size), sizeof(size));

    for (uint8_t b : data) {
        if (b == 0xFF) {
            cout.put(0xFE);
            cout.put(0x01);
        } else if (b == 0xFE) {
            cout.put(0xFE);
            cout.put(0x00);
        } else {
            cout.put(b);
        }
    }

    return 0;
}
EOF
    g++ -O3 -o /app/bin/oracle_ingestor /app/bin/oracle_ingestor.cpp
    chmod +x /app/bin/oracle_ingestor

    # Create Flask App
    cat << 'EOF' > /app/services/app.py
from flask import Flask, request
import redis
import hashlib
import struct

app = Flask(__name__)
r = redis.Redis(host='127.0.0.1', port=6379, db=0)

@app.route('/upload', methods=['POST'])
def upload():
    name = request.args.get('name')
    if not name:
        return "Missing name", 400

    data = request.get_data()
    if len(data) < 8:
        return "Too short", 400

    magic = data[:4]
    if magic != b'ARTI':
        return "Bad magic", 400

    size = struct.unpack('<I', data[4:8])[0]
    payload = data[8:]

    unstuffed = bytearray()
    i = 0
    while i < len(payload):
        if payload[i] == 0xFE:
            if i + 1 >= len(payload):
                return "Bad stuffing", 400
            if payload[i+1] == 0x01:
                unstuffed.append(0xFF)
            elif payload[i+1] == 0x00:
                unstuffed.append(0xFE)
            else:
                return "Bad stuffing byte", 400
            i += 2
        else:
            unstuffed.append(payload[i])
            i += 1

    if len(unstuffed) != size:
        return "Size mismatch", 400

    h = hashlib.sha256(unstuffed).hexdigest()
    r.set(f"artifact:hash:{name}", h)

    return "OK", 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Create Nginx Config
    cat << 'EOF' > /app/services/nginx.conf
events {}
http {
    server {
        listen 8080;
        location /upload {
            proxy_pass http://127.0.0.1:5000/upload;
        }
    }
}
EOF

    # Create start_services script
    cat << 'EOF' > /app/services/start_services.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /app/services/nginx.conf
nohup python3 /app/services/app.py > /tmp/flask.log 2>&1 &
sleep 2
EOF
    chmod +x /app/services/start_services.sh

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
