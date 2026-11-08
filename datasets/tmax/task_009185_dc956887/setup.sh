#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/server
    mkdir -p /home/user/loc_pipeline

    cat << 'EOF' > /home/user/server/raw_translations.jsonl
{"id": "btn_ok", "lang": "en", "text": "OK", "timestamp": 100}
{"id": "btn_ok", "lang": "en", "text": "Okay", "timestamp": 105}
{"id": "btn_cancel", "lang": "en", "text": "Cancel", "timestamp": 110}
{"id": "msg_error", "lang": "en", "text": "Error \u00xx", "timestamp": 120}
{"id": "btn_ok", "lang": "fr", "text": "D\u00e9ccord", "timestamp": 130}
{"id": "msg_error", "lang": "fr", "text": "Erreur", "timestamp": 140}
{"id": "lbl_save", "lang": "ENG", "text": "Save", "timestamp": 150}
{"id": "lbl_save", "lang": "en", "text": "Save", "timestamp": 160}
{"id": "msg_warn", "lang": "fr", "text": "Attention\uZZZZ", "timestamp": 170}
{"id": "btn_ok", "lang": "fr", "text": "D\u00e9ccord!", "timestamp": 180}
{"id": "msg_info", "lang": "fr", "text": "Info", "timestamp": 190}
{"id": "msg_success", "lang": "fr", "text": "Succ\u00e8s", "timestamp": 200}
EOF

    chmod -R 777 /home/user
