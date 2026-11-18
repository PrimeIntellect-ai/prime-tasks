#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_translations.jsonl
{"id": "btn_save", "lang": "fr-FR", "raw_text": "  Sauvegarder\n\t ", "timestamp": 1620000000, "contributor_score": 50}
{"id": "btn_save", "lang": "fr-FR", "raw_text": "Enregistrer", "timestamp": 1620000100, "contributor_score": 90}
{"id": "btn_save", "lang": "es-ES", "raw_text": "Guardar", "timestamp": 1620000000, "contributor_score": 85}
{"id": "msg_welcome", "lang": "es-ES", "raw_text": "«Bienvenidos» a la  aplicación", "timestamp": 1620000200, "contributor_score": 100}
{"id": "msg_welcome", "lang": "es-ES", "raw_text": "“Bienvenidos” a la aplicación", "timestamp": 1620000300, "contributor_score": 100}
{"id": "err_404", "lang": "fr-FR", "raw_text": "La page n’existe pas", "timestamp": 1620000400, "contributor_score": 80}
{"id": "err_404", "lang": "fr-FR", "raw_text": "  La   page n'existe pas ", "timestamp": 1620000500, "contributor_score": 80}
{"id": "err_404", "lang": "es-ES", "raw_text": "No \n encontrado", "timestamp": 1620000600, "contributor_score": 50}
EOF

    chmod -R 777 /home/user
