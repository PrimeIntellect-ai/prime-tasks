#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scikit-learn jsonschema numpy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/mlops
    cat << 'EOF' > /home/user/mlops/setup.py
import json
import random
import numpy as np

np.random.seed(42)
random.seed(42)

schema = {
    "type": "object",
    "properties": {
        "log_id": {"type": "integer"},
        "message": {"type": "string"},
        "features": {
            "type": "array",
            "items": {"type": "number"},
            "minItems": 2,
            "maxItems": 2
        },
        "recovery_time": {"type": "number"}
    },
    "required": ["log_id", "message", "features", "recovery_time"]
}

with open("/home/user/mlops/schema.json", "w") as f:
    json.dump(schema, f, indent=2)

words = ["disk", "cpu", "memory", "overload", "kernel", "panic", "process", "killed", "critical", "timeout", "connection", "lost", "network", "latency", "node", "failure"]

data = []
for i in range(500):
    num_words = random.randint(3, 8)
    msg_words = random.choices(words, k=num_words)

    # Inject query words to ensure some have high similarity
    if random.random() < 0.3:
        msg_words.extend(["critical", "timeout", "connection", "lost"])

    message = " ".join(msg_words)
    f1 = np.random.normal(0, 1)
    f2 = np.random.normal(0, 1)

    # True relationship: recovery = 3.5 * f1 - 2.1 * f2 + 10 + noise
    recovery = 3.5 * f1 - 2.1 * f2 + 10 + np.random.normal(0, 0.5)

    record = {
        "log_id": i,
        "message": message,
        "features": [float(f1), float(f2)],
        "recovery_time": float(recovery)
    }

    # Introduce schema violations
    if random.random() < 0.1:
        del record["recovery_time"]
    elif random.random() < 0.1:
        record["features"] = "invalid"

    data.append(record)

with open("/home/user/mlops/dataset.jsonl", "w") as f:
    for d in data:
        f.write(json.dumps(d) + "\n")
EOF
    python3 /home/user/mlops/setup.py

    chmod -R 777 /home/user
