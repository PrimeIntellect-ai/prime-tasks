#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /tmp/remote_l10n_source/
    mkdir -p /tmp/remote_l10n_dest/
    mkdir -p /home/user/

    cat << 'EOF' > /tmp/remote_l10n_source/en.json
[
  {"id": "btn_ok", "context": "ui", "text": "OK"},
  {"id": "btn_cancel", "context": "ui", "text": "Cancel"},
  {"id": "msg_welcome", "context": "home", "text": "Welcome to our app!"},
  {"id": "msg_error", "context": "home", "text": "An error occurred."},
  {"id": "nav_profile", "context": "nav", "text": "Profile"}
]
EOF

    cat << 'EOF' > /tmp/remote_l10n_source/es.json
[
  {"id": "btn_ok", "context": "ui", "text": "Aceptar"},
  {"id": "btn_cancel", "context": "ui", "text": null},
  {"id": "msg_error", "context": "home", "text": "Ocurrió un error."}
]
EOF

    cat << 'EOF' > /tmp/remote_l10n_source/fr.json
[
  {"id": "btn_ok", "context": "ui", "text": "D'accord"},
  {"id": "nav_profile", "context": "nav", "text": ""}
]
EOF

    cat << 'EOF' > /home/user/glossary.csv
id,lang,text
btn_cancel,es,Cancelar
btn_cancel,fr,Annuler
msg_error,fr,Une erreur est survenue.
EOF

    chown -R user:user /tmp/remote_l10n_source/ /tmp/remote_l10n_dest/ /home/user/
    chmod -R 777 /home/user
    chmod -R 777 /tmp/remote_l10n_source/ /tmp/remote_l10n_dest/
