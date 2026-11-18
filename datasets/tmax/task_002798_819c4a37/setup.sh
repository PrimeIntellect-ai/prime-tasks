#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget tar
    pip3 install pytest

    mkdir -p /app
    pip3 download --no-binary :all: PyJWT==2.8.0 -d /app
    tar -xzf /app/PyJWT-2.8.0.tar.gz -C /app
    mv /app/PyJWT-2.8.0 /app/pyjwt-2.8.0
    rm /app/PyJWT-2.8.0.tar.gz

    # Perturb pyproject.toml
    sed -i 's/requires = .*/requires = ["flit_core >=3.2,<4.0"/' /app/pyjwt-2.8.0/pyproject.toml

    # Create user
    useradd -m -s /bin/bash user || true

    # Generate logs
    cat << 'EOF' > /app/generate_logs.py
import json
import random
import jwt

OLD_KEY = "legacy_secret_992"
NEW_KEY = "rotated_secure_key_2024"

with open("/home/user/api_requests.log", "w") as f_all, \
     open("/app/truth_valid.log", "w") as f_valid, \
     open("/app/truth_invalid.log", "w") as f_invalid:

    for i in range(10000):
        req = {"request_id": i, "endpoint": "/api/data"}

        choice = random.choice(["new", "old", "forged"])
        payload = {"user_id": i}

        if choice == "new":
            token = jwt.encode(payload, NEW_KEY, algorithm="HS256")
            req["headers"] = {"Authorization": f"Bearer {token}"}
            line = json.dumps(req)
            f_all.write(line + "\n")
            f_valid.write(line + "\n")
        else:
            if choice == "old":
                token = jwt.encode(payload, OLD_KEY, algorithm="HS256")
            else:
                token = jwt.encode(payload, "random_key", algorithm="HS256")

            req["headers"] = {"Authorization": f"Bearer {token}"}
            line = json.dumps(req)
            f_all.write(line + "\n")

            req["headers"]["Authorization"] = "Bearer [REDACTED_CWE312]"
            f_invalid.write(json.dumps(req) + "\n")
EOF

    # We need jwt to generate logs, so install it temporarily
    pip3 install PyJWT==2.8.0
    python3 /app/generate_logs.py
    pip3 uninstall -y PyJWT

    # Create verify script
    cat << 'EOF' > /app/verify_accuracy.py
import sys
import json

def load_logs(filepath):
    try:
        with open(filepath, 'r') as f:
            return [json.loads(line) for line in f]
    except FileNotFoundError:
        return []

valid_preds = load_logs('/home/user/valid_requests.log')
invalid_preds = load_logs('/home/user/invalid_requests.log')
valid_gt = load_logs('/app/truth_valid.log')
invalid_gt = load_logs('/app/truth_invalid.log')

correct = 0
total = len(valid_gt) + len(invalid_gt)

for pred in valid_preds:
    if pred in valid_gt:
        correct += 1

for pred in invalid_preds:
    if pred in invalid_gt:
        correct += 1

accuracy = correct / total if total > 0 else 0
print(f"Accuracy: {accuracy}")
if accuracy >= 0.99:
    sys.exit(0)
else:
    sys.exit(1)
EOF

    chmod -R 777 /home/user
