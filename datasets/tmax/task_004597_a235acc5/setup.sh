#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ wget
    pip3 install pytest

    mkdir -p /home/user
    wget -O /home/user/json.hpp https://github.com/nlohmann/json/releases/download/v3.11.2/json.hpp

    cat << 'EOF' > /home/user/translations.jsonl
{"key": "btn_submit", "lang": "en", "text": "Submit"}
{"key": "btn_submit", "lang": "fr", "text": "Soumettre"}
{"key": "btn_cancel", "lang": "en", "text": "Cancel"}
{"key": "btn_cancel", "lang": "fr", "text": "Annuler"}
{"key": "invalid-key!", "lang": "en", "text": "Bad"}
{"key": "greeting", "lang": "EN", "text": "Uppercase lang bad"}
{"key": "error_msg", "lang": "es", "text": "Error \u00ZZZZ bad unicode"}
{"key": "success", "lang": "es", "text": "Éxito"}
{"key": "btn_submit", "lang": "en", "text": "Submit Updated"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
