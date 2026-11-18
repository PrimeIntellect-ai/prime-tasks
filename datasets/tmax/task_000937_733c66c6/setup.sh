#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip dnsmasq nginx gcc gdb tcpdump curl dnsutils sudo
    pip3 install pytest flask

    mkdir -p /home/user/sandbox
    mkdir -p /home/user/evidence
    mkdir -p /app/verifier/corpus/evil
    mkdir -p /app/verifier/corpus/clean

    # Sandbox config files
    cat << 'EOF' > /home/user/sandbox/start_sandbox.sh
#!/bin/bash
dnsmasq -C /home/user/sandbox/dnsmasq.conf
nginx -c /home/user/sandbox/nginx.conf
python3 /home/user/sandbox/sinkhole.py &
EOF
    chmod +x /home/user/sandbox/start_sandbox.sh

    cat << 'EOF' > /home/user/sandbox/dnsmasq.conf
# TODO: Add C2 domain resolution
EOF

    cat << 'EOF' > /home/user/sandbox/nginx.conf
events {}
http {
    server {
        # TODO: Configure listening port and proxy
    }
}
EOF

    cat << 'EOF' > /home/user/sandbox/sinkhole.py
from flask import Flask, jsonify
app = Flask(__name__)
@app.route('/ping')
def ping():
    return jsonify({"status": "sinkholed"})
if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Evidence files
    cat << 'EOF' > /home/user/evidence/parser.c
#include <stdio.h>
#include <stdlib.h>

int parse_payload(unsigned char *payload) {
    int len = payload[1];
    char buf[256];
    int i = 0;
    // Off-by-one: <= instead of <
    while(i <= len) {
        buf[i] = payload[2+i];
        i++;
    }
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if(!f) return 1;
    unsigned char payload[1024];
    fread(payload, 1, 1024, f);
    fclose(f);
    parse_payload(payload);
    return 0;
}
EOF

    echo "dummy pcap data" > /home/user/evidence/capture.pcap
    echo "dummy core dump" > /home/user/evidence/core.parser

    # Corpus generation
    python3 -c '
import os
import random

evil_dir = "/app/verifier/corpus/evil"
clean_dir = "/app/verifier/corpus/clean"

for i in range(50):
    with open(os.path.join(evil_dir, f"evil_{i}.bin"), "wb") as f:
        # byte 1 length >= 255 to trigger overflow in buf[256] with <=
        f.write(bytes([0x00, 255] + [0x41]*260))

for i in range(50):
    with open(os.path.join(clean_dir, f"clean_{i}.bin"), "wb") as f:
        # byte 1 length < 255
        length = random.randint(10, 200)
        f.write(bytes([0x00, length] + [0x42]*(length + 5)))
'

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
