#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app/.hidden
    mkdir -p /app/bin

    cat << 'EOF' > /tmp/setup.py
import os
import json
import base64
import hmac
import hashlib
import random
from datetime import datetime, timedelta
from PIL import Image, ImageDraw

# 1. auth.log
auth_log = """Jan 10 10:00:01 server sshd[123]: Failed password for admin from 192.168.1.10 port 33452 ssh2
Jan 10 10:00:05 server sshd[123]: Failed password for admin from 192.168.1.10 port 33452 ssh2
""" + "\n".join([f"Jan 10 10:0{i//10}:{i%10}0 server sshd[123]: Failed password for admin from 192.168.1.10 port 33452 ssh2" for i in range(1, 51)]) + """
Jan 10 10:05:00 server sshd[123]: Accepted password for admin from 192.168.1.10 port 33452 ssh2
Jan 10 10:06:00 server sshd[125]: Accepted password for user from 10.0.0.5 port 22341 ssh2
"""
with open('/app/auth.log', 'w') as f:
    f.write(auth_log)

# 2. binaries and manifest
with open('/app/bin/ls', 'w') as f: f.write("#!/bin/bash\nls $@")
with open('/app/bin/cat', 'w') as f: f.write("#!/bin/bash\ncat $@")
with open('/app/bin/grep', 'w') as f: f.write("#!/bin/bash\ngrep $@")
with open('/app/bin/netstat', 'w') as f: f.write("#!/bin/bash\necho 'normal netstat'")

def get_hash(path):
    with open(path, 'rb') as f:
        return hashlib.sha256(f.read()).hexdigest()

manifest = ""
for b in ['ls', 'cat', 'grep', 'netstat']:
    manifest += f"{get_hash('/app/bin/'+b)}  {b}\n"
with open('/app/manifest.sha256', 'w') as f:
    f.write(manifest)

# tamper netstat
with open('/app/bin/netstat', 'w') as f: f.write("#!/bin/bash\necho 'owned'")

# 3. generate records
MASTER_KEY = b"c7b8d9a1f2e3"
ATTACKER_IP = "192.168.1.10"

obfuscated = []
true_logs = []

random.seed(42)
for i in range(1000):
    is_valid = i < 900
    ip = ATTACKER_IP if random.random() < 0.2 else f"10.0.0.{random.randint(1, 255)}"
    timestamp = (datetime(2023, 1, 1) + timedelta(minutes=i)).isoformat()
    event = random.choice(["login", "logout", "read", "write"])

    msg = f"{ip}|{timestamp}|{event}".encode()
    sig = hmac.new(MASTER_KEY, msg, hashlib.sha256).hexdigest()[:10]

    if not is_valid:
        sig = "0000000000"

    record = {"ip": ip, "timestamp": timestamp, "event": event, "signature": sig}
    b64_record = base64.b64encode(json.dumps(record).encode()).decode()
    obfuscated.append(b64_record)

    if is_valid:
        true_logs.append({
            "ip": ip,
            "timestamp": timestamp,
            "event": event,
            "compromised": ip == ATTACKER_IP
        })

with open('/app/obfuscated_records.txt', 'w') as f:
    f.write("\n".join(obfuscated))

with open('/app/.hidden/true_logs.json', 'w') as f:
    json.dump(true_logs, f)

# 4. create image
img = Image.new('RGB', (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 40), "MASTER_KEY=c7b8d9a1f2e3", fill=(0, 0, 0))
img.save('/app/evidence.png')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
