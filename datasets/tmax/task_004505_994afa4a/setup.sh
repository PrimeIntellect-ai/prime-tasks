#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr ffmpeg jq
    pip3 install pytest opencv-python-headless numpy

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate the video
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

width, height = 800, 600
fps = 10
duration = 5
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/audit_session.mp4', fourcc, fps, (width, height))

for i in range(fps * duration):
    frame = np.zeros((height, width, 3), dtype=np.uint8)
    if i >= 40:
        text = "[WARN] Query executed: DROP TABLE compliance_records; -- SESSION_ID: 77B-XYZ-912"
        cv2.putText(frame, text, (10, 300), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)
    out.write(frame)

out.release()
EOF
    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    # Clean 1: Proper match and safe lookup
    cat << 'EOF' > /app/corpus/clean/c1.json
[
  { "$match": { "tenant_id": "T-100", "status": "active" } },
  { "$lookup": { "from": "orders", "localField": "id", "foreignField": "user_id", "as": "orders" } }
]
EOF

    # Clean 2: Only match
    cat << 'EOF' > /app/corpus/clean/c2.json
[
  { "$match": { "tenant_id": "T-200" } },
  { "$group": { "_id": "$region", "total": { "$sum": 1 } } }
]
EOF

    # Evil 1: Missing tenant_id in match
    cat << 'EOF' > /app/corpus/evil/e1.json
[
  { "$match": { "status": "active" } },
  { "$project": { "name": 1 } }
]
EOF

    # Evil 2: match is not the first stage
    cat << 'EOF' > /app/corpus/evil/e2.json
[
  { "$sort": { "created_at": -1 } },
  { "$match": { "tenant_id": "T-100" } }
]
EOF

    # Evil 3: accesses restricted collection in lookup
    cat << 'EOF' > /app/corpus/evil/e3.json
[
  { "$match": { "tenant_id": "T-300" } },
  { "$lookup": { "from": "system.users", "localField": "id", "foreignField": "id", "as": "u" } }
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
