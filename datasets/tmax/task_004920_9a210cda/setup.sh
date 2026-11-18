#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip nginx curl jq gawk
pip3 install pytest flask

mkdir -p /app/gateway /app/services /app/verifier

cat << 'EOF' > /app/gateway/nginx.conf
events {}
http {
    server {
        listen 8080;
        # TODO: Add proxy_pass for /meta/ and /records/
    }
}
EOF

cat << 'EOF' > /app/services/meta_service.py
from flask import Flask, jsonify
app = Flask(__name__)

@app.route('/experiments')
def exps():
    return jsonify(["exp_101", "exp_102"])

@app.route('/schema/<exp_id>')
def schema(exp_id):
    if exp_id == "exp_101":
        return jsonify({"s1": "tp53_level", "s2": "brca1_level"})
    elif exp_id == "exp_102":
        return jsonify({"s1": "egfr_level", "s2": "myc_level"})
    return jsonify({})

if __name__ == '__main__':
    app.run(port=5001)
EOF

cat << 'EOF' > /app/services/data_service.py
from flask import Flask, jsonify
app = Flask(__name__)

@app.route('/<exp_id>')
def records(exp_id):
    if exp_id == "exp_101":
        return jsonify([
            {"timestamp": 1690001000, "status": "valid", "s1": 0.45, "s2": 1.2},
            {"timestamp": 1690001001, "status": "corrupted", "s1": 0.1, "s2": 0.1}
        ])
    elif exp_id == "exp_102":
        return jsonify([
            {"timestamp": 1690002000, "status": "valid", "s1": 3.1, "s2": 4.2},
            {"timestamp": 1690002001, "status": "invalid", "s1": 0.0, "s2": 0.0}
        ])
    return jsonify([])

if __name__ == '__main__':
    app.run(port=5002)
EOF

cat << 'EOF' > /app/start_services.sh
#!/bin/bash
nginx -c /app/gateway/nginx.conf &
python3 /app/services/meta_service.py &
python3 /app/services/data_service.py &
sleep 2
EOF
chmod +x /app/start_services.sh

cat << 'EOF' > /app/verifier/score.py
import sys
import json

def load_data(filepath):
    try:
        with open(filepath, 'r') as f:
            data = json.load(f)
        return set(frozenset(d.items()) for d in data)
    except Exception as e:
        return set()

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Metric: 0.0")
        sys.exit(1)

    pred = load_data(sys.argv[1])
    truth = load_data(sys.argv[2])

    if not truth:
        print("Metric: 0.0")
        sys.exit(1)

    intersection = len(pred.intersection(truth))
    union = len(pred.union(truth))

    jaccard = intersection / union if union > 0 else 0.0
    print(f"Metric: {jaccard}")
    if jaccard >= 0.99:
        sys.exit(0)
    else:
        sys.exit(1)
EOF

cat << 'EOF' > /app/verifier/ground_truth.json
[
  {
    "experiment_id": "exp_101",
    "timestamp": 1690001000,
    "tp53_level": 0.45,
    "brca1_level": 1.2
  },
  {
    "experiment_id": "exp_102",
    "timestamp": 1690002000,
    "egfr_level": 3.1,
    "myc_level": 4.2
  }
]
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /app
chmod -R 777 /home/user
