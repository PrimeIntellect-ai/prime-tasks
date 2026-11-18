#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/locales.json
[
  {"id": "btn_save", "en": "Save", "fr": "Sauvegarder"},
  {"id": "btn_cancel", "en": "Cancel", "fr": "Annuler"},
  {"id": "msg_hello", "en": "Hello World", "fr": null},
  {"id": "msg_error", "en": "An unexpected error occurred during the process", "fr": "Erreur"},
  {"id": "btn_ok", "en": "OK", "fr": "OK"},
  {"id": "msg_welcome", "en": "Welcome", "fr": ""},
  {"id": "lbl_status", "en": "Status", "fr": "Statut"}
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
