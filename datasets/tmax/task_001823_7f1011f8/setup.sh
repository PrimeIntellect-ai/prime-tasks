#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server tcpdump
    pip3 install pytest flask redis requests scapy

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/aggregator.py
from flask import Flask, request, jsonify
import redis
import json

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6380, db=0)

@app.route('/record', methods=['POST'])
def record():
    data = request.get_data(as_text=True)
    payload = json.loads(data)
    value = float(payload['value'])

    count = r.incr('count')
    sum_val = r.incrbyfloat('sum', value)
    sum_sq = r.incrbyfloat('sum_sq', value**2)

    return jsonify({"status": "ok"})

@app.route('/metrics', methods=['GET'])
def metrics():
    count = int(r.get('count') or 0)
    if count < 2:
        return jsonify({"variance": 0.0})

    sum_val = float(r.get('sum') or 0.0)
    sum_sq = float(r.get('sum_sq') or 0.0)

    variance = (sum_sq - (sum_val**2) / count) / (count - 1)

    return jsonify({"variance": variance})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    cat << 'EOF' > /home/user/app/sensor.py
import requests
import time
import random

while True:
    val = random.uniform(10, 20)
    try:
        requests.post("http://localhost:5000/record", json={"value": val})
    except:
        pass
    time.sleep(1)
EOF

    cat << 'EOF' > /home/user/app/start.sh
#!/bin/bash
redis-server --daemonize yes
python3 /home/user/app/aggregator.py &
python3 /home/user/app/sensor.py &
wait
EOF
    chmod +x /home/user/app/start.sh

    cat << 'EOF' > /tmp/gen_pcap.py
from scapy.all import *
pkts = []
pkts.append(IP(dst="127.0.0.1")/TCP(dport=5000)/Raw(load="POST /record HTTP/1.1\r\n\r\n{\"value\": 12.4,}"))
pkts.append(IP(dst="127.0.0.1")/TCP(dport=5000)/Raw(load="POST /record HTTP/1.1\r\n\r\n{\"value\": \"1.24e1\"}"))
wrpcap("/home/user/app/traffic.pcap", pkts)
EOF
    python3 /tmp/gen_pcap.py
    rm /tmp/gen_pcap.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
