#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq parallel gawk sed
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_translations.jsonl
{"timestamp": 1600000001, "string_id": "btn_greet", "locale": "es-ES", "text": "Hola \u00e1"}
{"timestamp": 1600000002, "string_id": "txt_desc", "locale": "es-ES", "text": "A \u00e9 B"}
{"timestamp": 1600000003, "string_id": "btn_cancel", "locale": "es-ES", "text": "X"}
{"timestamp": 1600000004, "string_id": "btn_greet", "locale": "es-ES", "text": "Hol \u00e1"}
{"timestamp": 1600000005, "string_id": "btn_help", "locale": "es-ES", "text": "YZ"}
{"timestamp": 1600000001, "string_id": "btn_greet", "locale": "fr-FR", "text": "Oui \u00e7a"}
{"timestamp": 1600000006, "string_id": "btn_help", "locale": "es-ES", "text": "\u00a1Ojo!"}
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
