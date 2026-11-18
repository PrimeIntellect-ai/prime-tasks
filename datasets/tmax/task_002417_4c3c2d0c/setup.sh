#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install pytest flask redis

    mkdir -p /app/api
    mkdir -p /home/user

    cat << 'EOF' > /app/redis.conf
port 0
unixsocket /tmp/redis.sock
daemonize yes
EOF

    cat << 'EOF' > /app/api/app.py
from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route('/predict', methods=['POST'])
def predict():
    data = request.json
    feature = data.get('feature', 0.0)
    # Simple dummy regression model
    prediction = feature * 2.5 + 1.1
    return jsonify({"prediction": prediction})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server /app/redis.conf
python3 /app/api/app.py &
sleep 2
EOF
    chmod +x /app/start_services.sh

    cat << 'EOF' > /app/oracle_pipeline.py
import sys
import json
import random
import urllib.request
import redis

def main():
    if len(sys.argv) < 2:
        sys.exit(1)

    data = json.loads(sys.argv[1])
    user_id = data['user_id']
    v1 = float(data['v1'])
    v2 = float(data['v2'])

    base_array = [v1, v2, v1 - v2, v1 + v2]
    rng = random.Random(user_id)

    means = []
    for _ in range(100):
        sample = rng.choices(base_array, k=4)
        means.append(sum(sample) / 4.0)

    engineered_feature = sum(means) / 100.0

    r = redis.Redis(host='127.0.0.1', port=6379, db=0)
    try:
        val = r.get(f"multiplier_{user_id}")
        multiplier = float(val) if val else 1.0
    except:
        multiplier = 1.0

    final_feature = engineered_feature * multiplier

    payload = json.dumps({"feature": final_feature}).encode('utf-8')
    req = urllib.request.Request('http://127.0.0.1:5000/predict', data=payload, headers={'Content-Type': 'application/json'})

    with urllib.request.urlopen(req) as response:
        res_data = json.loads(response.read().decode())
        prediction = res_data['prediction']

    print(f"{prediction:.4f}")

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
