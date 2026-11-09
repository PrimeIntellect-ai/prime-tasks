#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl jq
    pip3 install pytest flask scikit-learn pandas requests

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/dataset.csv
id,text,label
1,apple pie is great,1
2,car engine broke,0
3,banana split,1
4,replace the spark plug,0
5,fresh fruit salad,1
6,oil change needed,0
7,sweet strawberry,1
8,flat tire,0
9,juicy orange,1
10,brake fluid leak,0
11,mango smoothie,1
12,transmission failure,0
13,blueberry muffin,1
14,headlight is out,0
15,peach cobbler,1
16,steering wheel stuck,0
17,grape juice,1
18,exhaust pipe rusted,0
19,cherry tart,1
20,battery is dead,0
EOF

    cat << 'EOF' > /home/user/service.py
from flask import Flask, request, jsonify
import time
import hashlib

app = Flask(__name__)

def generate_deterministic_embedding(text):
    # Returns a 5-dim vector based on the text hash
    h = hashlib.md5(text.encode()).digest()
    return [(b / 255.0) for b in h[:5]]

@app.route('/embed/model_alpha', methods=['POST'])
def model_alpha():
    data = request.json
    time.sleep(0.01) # Faster
    return jsonify({"embedding": generate_deterministic_embedding(data.get('text', ''))})

@app.route('/embed/model_beta', methods=['POST'])
def model_beta():
    data = request.json
    time.sleep(0.05) # Slower
    return jsonify({"embedding": generate_deterministic_embedding(data.get('text', ''))})

if __name__ == '__main__':
    app.run(port=5000)
EOF

    chmod -R 777 /home/user
