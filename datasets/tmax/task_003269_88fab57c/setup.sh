#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-numpy python3-scipy python3-yaml
    pip3 install pytest flask redis

    mkdir -p /home/user/pipeline /app/corpus/clean /app/corpus/evil

    # Generate Clean Corpus (N(5, 1))
    python3 -c '
import json, random
for i in range(20):
    data = [random.gauss(5, 1) for _ in range(200)]
    with open(f"/app/corpus/clean/sample_{i}.json", "w") as f: json.dump(data, f)
'

    # Generate Evil Corpus (Mixture: 0.8 * N(5, 1) + 0.2 * N(0, 0.5))
    python3 -c '
import json, random
for i in range(20):
    data = [random.gauss(0, 0.5) if random.random() < 0.2 else random.gauss(5, 1) for _ in range(200)]
    with open(f"/app/corpus/evil/sample_{i}.json", "w") as f: json.dump(data, f)
'

    cat << 'EOF' > /home/user/pipeline/config.yaml
redis_host: "localhost"
redis_port: 6379 # intentionally wrong
metrics_url: "http://localhost:5000/report" # intentionally wrong
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
