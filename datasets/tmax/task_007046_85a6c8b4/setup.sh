#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import csv
import hashlib

os.makedirs('/home/user/incoming', exist_ok=True)

# Create tm_master.csv
tm_data = [
    ("Hello", "es", "Hola"),
    ("Save changes", "fr", "Enregistrer les modifications"),
    ("Cancel", "de", "Abbrechen")
]

with open('/home/user/tm_master.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["string_id", "en_source", "locale", "translation"])
    for en, loc, trans in tm_data:
        str_id = hashlib.md5(en.encode('utf-8')).hexdigest()
        writer.writerow([str_id, en, loc, trans])

# Create batch_01.jsonl
jsonl_content = r"""{"en": "Hello", "locale": "fr", "trans": "Bonjour"}
{"en": "Save changes", "locale": "fr", "trans": "Enregistrer les modifications"}
{"en": "Welcome back", "locale": "es", "trans": "Bienvenido de nuevo \u00Z"}
{"en": "File not found", "locale": "de", "trans": "Datei nicht gefunden"}
{"en": "Loading...", "locale": "es", "trans": "Cargando..."}
{"en": "Retry", "locale": "es", "trans": "Reintentar"}
{"en": "Skip", "locale": "de", "trans": "Überspringen"}
{"en": "Delete account", "locale": "de", "trans": "Konto l\u00-schen"}
{"en": "Next", "locale": "fr", "trans": "Suivant"}
{"en": "Previous", "locale": "fr", "trans": "Précédent"}
"""

with open('/home/user/incoming/batch_01.jsonl', 'w', encoding='utf-8') as f:
    f.write(jsonl_content)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
