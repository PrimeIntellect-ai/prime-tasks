#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_data.py
import json
import random
from datetime import datetime, timedelta
import hashlib

random.seed(42)

def make_hash(sl, tl, st):
    return hashlib.md5(f"{sl}_|{tl}_|{st}".encode('utf-8')).hexdigest()

data = []
start_time = datetime(2023, 1, 1, 12, 0, 0)

# Generate normal EN-FR data
base_texts = [
    "This is a standard sentence.",
    "Please click the button to continue.",
    "Your password has been reset successfully.",
    "Welcome to our new platform.",
    "Enter your email address.",
    "The operation completed with errors.",
    "Save your changes before exiting.",
    "Contact support for more information.",
    "User profile updated.",
    "Download the latest version here."
]

id_counter = 1

# Generate 50 normal records
for i in range(50):
    src = random.choice(base_texts) + " " + "".join(random.choices("abcdefghijklmnopqrstuvwxyz", k=random.randint(5, 15)))
    tgt = src * 1 + "".join(random.choices("abcdefghijklmnopqrstuvwxyz", k=random.randint(1, 5))) # Roughly 1.0 - 1.2 ratio
    ts = start_time + timedelta(minutes=i*10)
    data.append({
        "id": f"NORM_{id_counter}",
        "timestamp": ts.isoformat(),
        "source_lang": "en",
        "target_lang": "fr",
        "source_text": src,
        "target_text": tgt
    })
    id_counter += 1

# Add an anomaly
src = "Short text."
tgt = "This is a ridiculously long translation that makes absolutely no sense and should definitely trigger the anomaly detection system because its length ratio is huge."
ts = start_time + timedelta(minutes=550)
data.append({
    "id": f"ANOMALY_1",
    "timestamp": ts.isoformat(),
    "source_lang": "en",
    "target_lang": "fr",
    "source_text": src,
    "target_text": tgt
})

# Add some duplicates
for i in range(5):
    orig = data[i]
    # Older duplicate (should be ignored)
    data.append({
        "id": f"DUP_OLD_{i}",
        "timestamp": (datetime.fromisoformat(orig["timestamp"]) - timedelta(days=1)).isoformat(),
        "source_lang": "en",
        "target_lang": "fr",
        "source_text": orig["source_text"],
        "target_text": "Bad translation"
    })
    # Newer duplicate (should overwrite)
    data.append({
        "id": f"DUP_NEW_{i}",
        "timestamp": (datetime.fromisoformat(orig["timestamp"]) + timedelta(days=1)).isoformat(),
        "source_lang": "en",
        "target_lang": "fr",
        "source_text": orig["source_text"],
        "target_text": orig["target_text"] + " updated"
    })

# Add other languages (should be filtered out)
for i in range(10):
    data.append({
        "id": f"OTHER_{i}",
        "timestamp": (start_time + timedelta(minutes=i*15)).isoformat(),
        "source_lang": "en",
        "target_lang": "es",
        "source_text": "Hello",
        "target_text": "Hola"
    })

# Add another anomaly later
src = "Another short text."
tgt = "a" # Extremely short
ts = start_time + timedelta(days=2, minutes=100)
data.append({
    "id": f"ANOMALY_2",
    "timestamp": ts.isoformat(),
    "source_lang": "en",
    "target_lang": "fr",
    "source_text": src,
    "target_text": tgt
})

random.shuffle(data)

with open("/home/user/tm_updates.jsonl", "w") as f:
    for d in data:
        f.write(json.dumps(d) + "\n")
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    chmod -R 777 /home/user
