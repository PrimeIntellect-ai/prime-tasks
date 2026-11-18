#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        python3-opencv \
        gcc \
        libc6-dev

    pip3 install --default-timeout=100 pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /tmp/setup.py
import cv2
import numpy as np
import os

# Generate video
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/config_blinks.mp4', fourcc, 24.0, (100, 100))

for i in range(1500):
    if i in [142, 512, 1024]:
        frame = np.full((100, 100, 3), 255, dtype=np.uint8)
    else:
        frame = np.zeros((100, 100, 3), dtype=np.uint8)
    out.write(frame)
out.release()

# Generate audit log
with open('/app/audit_log.csv', 'w') as f:
    f.write('commit_id,service_name,config_snippet\n')
    f.write('1,other-service,nothing\n')
    f.write('142,auth-service,"{ \\"aws_key\\": \\"AKIAX5555555555YYYYY\\", \\"role\\": \\"admin\\" }"\n')
    f.write('200,test-service,test\n')
    f.write('512,payment-gateway,"key=AKIA1111111111111111;mode=prod"\n')
    f.write('1000,test-service,test\n')
    f.write('1024,auth-service,"{ \\"token\\": \\"standard_token\\", \\"refresh\\": false }"\n')

# Generate corpus
for i in range(50):
    with open(f'/app/corpus/clean/file_{i}.txt', 'w') as f:
        f.write('AKIA_NOT_SECRET\nAKIA123\nAKIA1234567890abcdef\n')
    with open(f'/app/corpus/evil/file_{i}.txt', 'w') as f:
        f.write('AKIAABCDEFGHIJKLMNOP\n')
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
