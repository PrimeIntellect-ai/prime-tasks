#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg
pip3 install --no-cache-dir pytest
pip3 install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
pip3 install --no-cache-dir openai-whisper gTTS

mkdir -p /app/data
mkdir -p /opt

cat << 'EOF' > /tmp/setup_data.py
import json, random
from gtts import gTTS
import os

random.seed(42)

roles = [f"role_{i}" for i in range(20)]
perms = [{"role_identifier": r, "access_level": random.choice(["read", "write", "admin"]), "allowed_resources": ["res_A", "res_B"]} for r in roles]

users = []
for i in range(500):
    users.append({
        "user_id": i,
        "username": f"user_{i:03d}",
        "role_id": random.choice(roles),
        "is_active": random.choice([True, False]),
        "reputation_score": random.randint(0, 100)
    })

with open("/app/data/users.json", "w") as f:
    json.dump(users, f)

with open("/app/data/data_permissions.json", "w") as f:
    json.dump(perms, f)

text = "Hey, it's Alex. The user permissions aggregation is exploding because we're doing a cross join. The `users.json` and `data_permissions.json` shouldn't be joined on the raw arrays. You need to join the `role_id` from users to the `role_identifier` in permissions. Also, we only want to materialize this for users where `is_active` is true and their `reputation_score` is greater than or equal to 50. Once you join them, embed the permission details under a `permissions_graph` key in the user object. Finally, sort the whole result first by `reputation_score` descending, and then by `username` ascending alphabetically. The script just needs to take page number and page size and slice that sorted array. Thanks."
tts = gTTS(text)
tts.save("/app/engineer_voicemail.mp3")
EOF

python3 /tmp/setup_data.py
ffmpeg -i /app/engineer_voicemail.mp3 /app/engineer_voicemail.wav -y
rm /app/engineer_voicemail.mp3 /tmp/setup_data.py

cat << 'EOF' > /opt/oracle_query_fixer
#!/usr/bin/env python3
import sys, json

users_path = "/app/data/users.json"
perms_path = "/app/data/data_permissions.json"

with open(users_path) as f:
    users = json.load(f)
with open(perms_path) as f:
    perms = json.load(f)

perm_dict = {p['role_identifier']: p for p in perms}

joined = []
for u in users:
    if u.get('is_active') and u.get('reputation_score', 0) >= 50:
        role_id = u.get('role_id')
        if role_id in perm_dict:
            new_u = dict(u)
            new_u['permissions_graph'] = perm_dict[role_id]
            joined.append(new_u)

joined.sort(key=lambda x: (-x.get('reputation_score', 0), x.get('username', '')))

page_num = int(sys.argv[1])
page_size = int(sys.argv[2])

start = (page_num - 1) * page_size
end = start + page_size

print(json.dumps(joined[start:end], separators=(',', ':')))
EOF

chmod +x /opt/oracle_query_fixer

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
