#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/locales/updates
    mkdir -p /home/user/locales/output

    cat << 'EOF' > /tmp/setup.py
import os
import json
import csv

base_dir = "/home/user/locales"
updates_dir = os.path.join(base_dir, "updates")
output_dir = os.path.join(base_dir, "output")

# Create base.json
base_json = {
    "es": {"btn_submit": "Enviar", "btn_cancel": "Cancelar"},
    "fr": {"btn_submit": "Soumettre", "btn_cancel": "Annuler"},
    "de": {"btn_submit": "Einreichen", "btn_cancel": "Abbrechen"}
}
with open(os.path.join(base_dir, "base.json"), "w") as f:
    json.dump(base_json, f)

# Create CSV 1
csv1 = [
    ["string_id", "en", "es", "fr", "de"],
    ["msg_welcome", "Welcome", "Bienvenido", "Bienvenue", "Willkommen"],
    ["btn_cancel", "Cancel", "Cancelar_new", "Annuler_new", "Abbrechen_new"]
]
with open(os.path.join(updates_dir, "update1.csv"), "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerows(csv1)

# Create CSV 2
csv2 = [
    ["string_id", "en", "es", "fr", "de"],
    ["msg_goodbye", "Goodbye", "Adiós", "Au revoir", "Auf Wiedersehen"],
    ["lbl_error", "Error", "Error", "Erreur", "Fehler"]
]
with open(os.path.join(updates_dir, "update2.csv"), "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerows(csv2)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
