#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/loc_drop

    cat << 'EOF' > /home/user/loc_drop/generate_data.py
import json

data = [
    # Valid ar-SA, day 1
    {"ts": "2023-10-01T10:00:00Z", "lang": "ar-SA", "str_id": "btn.save", "text": "حفظ", "score": 10},
    {"ts": "2023-10-01T11:00:00Z", "lang": "ar-SA", "str_id": "btn.save", "text": "احفظ", "score": 15}, # Highest score
    {"ts": "2023-10-01T09:00:00Z", "lang": "ar-SA", "str_id": "btn.cancel", "text": "إلغاء", "score": 5},

    # Tie breaking logic (ja-JP, day 1)
    {"ts": "2023-10-01T14:00:00Z", "lang": "ja-JP", "str_id": "menu.file", "text": "ファイル", "score": 20}, # Earliest TS wins
    {"ts": "2023-10-01T15:00:00Z", "lang": "ja-JP", "str_id": "menu.file", "text": "ファイル...", "score": 20},

    # Corrupt data filtering
    {"ts": "2023-10-01T12:00:00Z", "lang": "ru-RU", "str_id": "err.network", "text": "Ошибка с\ufffdти", "score": 100}, # Should be filtered out
    {"ts": "2023-10-01T13:00:00Z", "lang": "ru-RU", "str_id": "err.network", "text": "Ошибка сети", "score": 10}, # Should be kept

    # Multi-day split (de-DE)
    {"ts": "2023-10-01T23:59:59Z", "lang": "de-DE", "str_id": "msg.welcome", "text": "Willkommen 🎉", "score": 50},
    {"ts": "2023-10-02T00:00:01Z", "lang": "de-DE", "str_id": "msg.welcome", "text": "Herzlich Willkommen", "score": 60},

    # Multi-string sorting
    {"ts": "2023-10-02T10:00:00Z", "lang": "de-DE", "str_id": "c", "text": "C", "score": 1},
    {"ts": "2023-10-02T10:00:00Z", "lang": "de-DE", "str_id": "a", "text": "A", "score": 1},
    {"ts": "2023-10-02T10:00:00Z", "lang": "de-DE", "str_id": "b", "text": "B", "score": 1},
]

with open('/home/user/loc_drop/raw_telemetry.jsonl', 'w', encoding='utf-8') as f:
    for row in data:
        f.write(json.dumps(row, ensure_ascii=False) + '\n')
EOF

    python3 /home/user/loc_drop/generate_data.py
    rm /home/user/loc_drop/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
