#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import json
import os

os.makedirs('/home/user', exist_ok=True)

data = [
    # Group: 2023-10, fr
    {"timestamp": "2023-10-01T10:00:00Z", "context_key": "btn.save", "lang": "fr", "source": "Save", "target": "Enregistrer"},
    {"timestamp": "2023-10-01T12:00:00Z", "context_key": "btn.save", "lang": "fr", "source": "Save", "target": "Sauvegarder"},
    {"timestamp": "2023-10-02T10:00:00Z", "context_key": "btn.cancel", "lang": "fr", "source": "Cancel", "target": "Annuler"},
    {"timestamp": "2023-10-03T10:00:00Z", "context_key": "btn.ok", "lang": "fr", "source": "OK", "target": "OK"},
    {"timestamp": "2023-10-04T10:00:00Z", "context_key": "btn.delete", "lang": "fr", "source": "Delete", "target": "Supprimer"},
    {"timestamp": "2023-10-05T10:00:00Z", "context_key": "btn.edit", "lang": "fr", "source": "Edit", "target": "Modifier"},
    {"timestamp": "2023-10-06T10:00:00Z", "context_key": "btn.close", "lang": "fr", "source": "Close", "target": "Fermer"},
    # Group: 2023-10, ja (with unnormalized unicode: fullwidth characters)
    {"timestamp": "2023-10-15T08:30:00Z", "context_key": "menu.file", "lang": "ja", "source": "File", "target": "ファイル"},
    {"timestamp": "2023-10-15T09:30:00Z", "context_key": "menu.file", "lang": "ja", "source": "File", "target": "フ\u30a1イル"},
    {"timestamp": "2023-10-15T10:30:00Z", "context_key": "menu.file", "lang": "ja", "source": "File", "target": "フ\u30a1\u30a4\u30eb"},
    {"timestamp": "2023-10-16T08:30:00Z", "context_key": "menu.edit", "lang": "ja", "source": "Edit", "target": "編集"},
    # Group: 2023-11, es
    {"timestamp": "2023-11-01T08:30:00Z", "context_key": "lbl.name", "lang": "es", "source": "Name", "target": "Nombre"},
    {"timestamp": "2023-11-02T08:30:00Z", "context_key": "lbl.age", "lang": "es", "source": "Age", "target": "Edad"},
    {"timestamp": "2023-11-03T08:30:00Z", "context_key": "lbl.email", "lang": "es", "source": "Email", "target": "Correo"},
]

with open('/home/user/translations_raw.jsonl', 'w', encoding='utf-8') as f:
    for d in data:
        f.write(json.dumps(d) + '\n')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
