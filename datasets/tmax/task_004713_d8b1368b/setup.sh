#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc espeak ffmpeg pocketsphinx
    pip3 install pytest

    mkdir -p /app

    # Generate the audio file
    espeak -w /app/analyst_notes.wav "The scoring matrix is: Add 5 points for every response missing a Content-Security-Policy header. Add 3 points for every response missing a Strict-Transport-Security header. Add 4 points for every Set-Cookie header that is missing the Secure or HttpOnly flag. Subtract 2 points if the Server header reveals a version number by containing a forward slash."

    # Generate the dataset
    cat << 'EOF' > /tmp/gen_data.py
import random

def generate_dataset():
    with open('/app/headers_dataset.txt', 'w') as f:
        for _ in range(500000):
            headers = ["HTTP/1.1 200 OK"]
            if random.random() > 0.5:
                headers.append("Content-Security-Policy: default-src 'self'")
            if random.random() > 0.5:
                headers.append("Strict-Transport-Security: max-age=31536000")
            if random.random() > 0.5:
                cookie = "Set-Cookie: session=123"
                if random.random() > 0.5:
                    cookie += "; Secure"
                if random.random() > 0.5:
                    cookie += "; HttpOnly"
                headers.append(cookie)
            if random.random() > 0.5:
                if random.random() > 0.5:
                    headers.append("Server: Apache/2.4.41")
                else:
                    headers.append("Server: Apache")
            f.write("\n".join(headers) + "\n\n")

generate_dataset()
EOF
    python3 /tmp/gen_data.py

    # Create naive_score.py
    cat << 'EOF' > /app/naive_score.py
import re
with open('/app/headers_dataset.txt', 'r') as f:
    data = f.read().split('\n\n')
score = 0
for block in data:
    if not block.strip(): continue
    score += 1
print(score)
EOF

    # Create hidden_ref_score.py
    cat << 'EOF' > /app/hidden_ref_score.py
import re
with open('/app/headers_dataset.txt', 'r') as f:
    data = f.read().split('\n\n')
score = 0
for block in data:
    if not block.strip(): continue
    if 'Content-Security-Policy:' not in block:
        score += 5
    if 'Strict-Transport-Security:' not in block:
        score += 3
    for line in block.split('\n'):
        if line.startswith('Set-Cookie:'):
            if 'Secure' not in line or 'HttpOnly' not in line:
                score += 4
        if line.startswith('Server:'):
            if '/' in line:
                score -= 2
print(score)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
