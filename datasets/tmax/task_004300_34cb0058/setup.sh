#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        libjansson-dev \
        libcjson-dev \
        ffmpeg \
        zbar-tools \
        imagemagick

    pip3 install pytest pandas qrcode Pillow

    mkdir -p /app
    mkdir -p /tmp/gen

    cat << 'EOF' > /tmp/gen/generate.py
import json
import random
import os
import qrcode
import subprocess
import pandas as pd

def is_vulnerable(event):
    # Rule 1
    r1 = (event.get("file_owner") == "root" and 
          len(event.get("file_permissions", "")) == 4 and 
          event["file_permissions"][0] in ['4', '6'])

    # Rule 2
    r2 = (event.get("cert_issuer") == event.get("cert_subject") and 
          not event.get("cert_in_trust_store", True))

    # Rule 3
    ui = event.get("user_input", "")
    r3 = any(sub in ui for sub in ["' OR ", "; DROP ", "--", "UNION SELECT"])

    return 1 if (r1 or r2 or r3) else 0

def generate_events(n, start_id=1):
    events = []
    for i in range(n):
        event = {
            "id": f"evt_{start_id + i:03d}",
            "file_owner": random.choice(["root", "user", "admin"]),
            "file_permissions": random.choice(["0755", "4755", "6444", "0644"]),
            "cert_issuer": random.choice(["CN=InternalCA", "CN=ExternalCA"]),
            "cert_subject": random.choice(["CN=InternalCA", "CN=AppServer"]),
            "cert_in_trust_store": random.choice([True, False]),
            "user_input": random.choice(["hello", "admin' OR 1=1--", "test; DROP TABLE users;", "normal input", "UNION SELECT * FROM users"])
        }
        events.append(event)
    return events

# Generate hidden test data
hidden_events = generate_events(1000, 100)
with open("/app/hidden_test_audit.json", "w") as f:
    json.dump(hidden_events, f, indent=2)

# Generate hidden expected output
expected = [{"id": e["id"], "is_vulnerable": is_vulnerable(e)} for e in hidden_events]
df = pd.DataFrame(expected)
df.to_csv("/app/hidden_expected.csv", index=False)

# Generate video data
video_events = generate_events(10, 1)
video_json_str = json.dumps(video_events)

# Split into 10 chunks
chunk_size = len(video_json_str) // 10
chunks = [video_json_str[i:i+chunk_size] for i in range(0, len(video_json_str), chunk_size)]
if len(chunks) > 10:
    chunks[9] += "".join(chunks[10:])
    chunks = chunks[:10]

for i, chunk in enumerate(chunks):
    qr = qrcode.QRCode(version=1, box_size=10, border=4)
    qr.add_data(chunk)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white")
    img.save(f"/tmp/gen/frame_{i:03d}.png")

# Create video from frames
subprocess.run([
    "ffmpeg", "-y", "-framerate", "1", "-i", "/tmp/gen/frame_%03d.png", 
    "-c:v", "libx264", "-r", "1", "-pix_fmt", "yuv420p", "/app/audit_transmission.mp4"
], check=True)

EOF

    python3 /tmp/gen/generate.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 755 /app
