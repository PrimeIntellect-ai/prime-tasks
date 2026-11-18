#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/loc_logs

    cat << 'EOF' > /home/user/loc_logs/file1.jsonl
{"timestamp": "2023-10-01T10:15:00Z", "loc_key": "greeting", "text": "Hola Mundo", "user_id": 1}
{"timestamp": "2023-10-01T10:15:00Z", "loc_key": "greeting", "text": "Hola Mundo", "user_id": 1}
{"timestamp": "2023-10-01T10:20:00Z", "loc_key": "city", "text": "M\u00e9xico", "user_id": 2}
{"timestamp": "2023-10-01T10:20:00Z", "loc_key": "city", "text": "M\\u00e9xico", "user_id": 2}
{"timestamp": "2023-10-01T11:05:00Z", "loc_key": "farewell", "text": "Adi\u00f3s", "user_id": 3}
EOF

    cat << 'EOF' > /home/user/loc_logs/file2.jsonl
{"timestamp": "2023-10-01T11:10:00Z", "loc_key": "farewell", "text": "Adi\\u00f3s", "user_id": 3}
{"timestamp": "2023-10-01T11:05:00Z", "loc_key": "farewell", "text": "Adi\\u00f3s", "user_id": 3}
{"timestamp": "2023-10-02T08:00:00Z", "loc_key": "button_ok", "text": "Aceptar", "user_id": 4}
EOF

    chmod -R 777 /home/user
