#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/loc_data

    cat << 'EOF' > /home/user/loc_data/eu_logs.csv
timestamp,lang_code,translation_key,usage_count
15/04/2023 14:30:00,FR-fr,btn_submit,10
15/04/2023 14:30:00,fr-FR,btn_submit,15
16/04/2023 09:15:22,de-DE,lbl_welcome,5
10/04/2023 08:00:00,es-ES,msg_error,42
16/04/2023 09:15:22,de_de,lbl_welcome,5
EOF

    cat << 'EOF' > /home/user/loc_data/asia_logs.json
[
  {"time_logged": 1681569000, "locale": "fr_FR", "key": "btn_submit", "uses": 20},
  {"time_logged": 1681636522, "locale": "ko-KR", "key": "lbl_welcome", "uses": 8},
  {"time_logged": 1681113600, "locale": "ja_JP", "key": "msg_error", "uses": 100},
  {"time_logged": 1681636522, "locale": "de-de", "key": "lbl_welcome", "uses": 12}
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
