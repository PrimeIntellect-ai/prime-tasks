#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    cat << 'EOF' > /tmp/setup.py
import os
import json
import base64

os.makedirs('/home/user', exist_ok=True)

data = [
    (1, "es", "utf-8", "Hola mundo"),
    (2, "ja", "shift_jis", "こんにちは"),
    (1, "es", "utf-8", "Hola mundo"),
    (3, "es", "windows-1252", "Adiós"),
    (4, "fr", "utf-8", "Bonjour"),
    (5, "ja", "shift_jis", "さようなら"),
    (6, "es", "utf-8", "Buenos días"),
    (7, "es", "utf-8", "Buenas noches"),
    (4, "fr", "utf-8", "Bonjour"),
    (8, "fr", "utf-8", "Merci"),
]

with open('/home/user/raw_translations.jsonl', 'w') as f:
    for tx_id, lang, charset, text in data:
        if charset == "windows-1252":
            raw_bytes = text.encode('cp1252')
        elif charset == "shift_jis":
            raw_bytes = text.encode('shift_jis')
        else:
            raw_bytes = text.encode('utf-8')

        b64 = base64.b64encode(raw_bytes).decode('ascii')
        record = {
            "tx_id": tx_id,
            "lang": lang,
            "charset": charset,
            "payload_b64": b64
        }
        f.write(json.dumps(record) + "\n")
EOF
    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
