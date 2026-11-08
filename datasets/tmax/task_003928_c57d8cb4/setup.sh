#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

# Install system dependencies
apt-get install -y gcc redis-server

# Install Python dependencies
pip3 install flask redis

# Create directories
mkdir -p /app/src /app/bin /app/tests /app/service

# Create /app/src/primer_score.c
cat << 'EOF' > /app/src/primer_score.c
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc != 3) return 1;
    char *target = argv[1];
    char *primer = argv[2];
    int score = 0;
    for (int i = 0; i < strlen(primer); i++) {
        if (target[i] == primer[i]) {
            score += 1;
        } else {
            score += 2; // BUG: Should be -= 2
        }
    }
    printf("%d\n", score);
    return 0;
}
EOF

# Create /app/tests/regression.sh
cat << 'EOF' > /app/tests/regression.sh
#!/bin/bash
gcc ../src/primer_score.c -o ../bin/primer_score
RES=$(../bin/primer_score ATGCGTAC ATTC)
if [ "$RES" != "1" ]; then
    echo "Regression test failed: expected 1, got $RES"
    exit 1
fi
echo "Pass"
EOF
chmod +x /app/tests/regression.sh

# Create /app/service/app.py
cat << 'EOF' > /app/service/app.py
import os, subprocess, json
from flask import Flask, request, jsonify
import redis

app = Flask(__name__)
r = redis.Redis(host='127.0.0.1', port=6379, db=0)

@app.route('/score', methods=['POST'])
def score():
    data = request.json
    target = data['target']
    primer = data['primer']

    # Needs to be changed by agent to /app/bin/primer_score
    cmd = ["/wrong/path/primer_score", target, primer]
    result = subprocess.run(cmd, capture_output=True, text=True)

    c_score = int(result.stdout.strip())
    threshold = int(r.get("motif_threshold") or 100)

    return jsonify({
        "score": c_score,
        "threshold_met": c_score >= threshold
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

# Ensure all files are accessible
chmod -R 777 /app

# Create user and set home permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
