#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest Levenshtein

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import json
import csv

home_dir = "/home/user"
os.makedirs(home_dir, exist_ok=True)

tm_data = [
    {"source": "Save file", "target": "Guardar archivo"},
    {"source": "Cancel operation", "target": "Cancelar"},
    {"source": "User profile", "target": "Perfil de usuario"},
    {"source": "Settings", "target": "Ajustes"},
    {"source": "Submit your changes", "target": "Enviar sus cambios"}
]

with open(os.path.join(home_dir, "tm.csv"), "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=["source", "target"])
    writer.writeheader()
    writer.writerows(tm_data)

activity_data = [
    {"time": "2023-10-01T10:15:00+0000", "source": "Save the file", "input": "Guardar el archivo"},
    {"time": "2023-10-01T12:45:00+0200", "source": "User profiles", "input": "Perfiles de usuario"},
    {"time": "2023-10-01T11:30:00-0400", "source": "Settings menu", "input": "Menú de configuración"},
    {"time": "2023-10-01T15:20:00+0000", "source": "Submit changes", "input": "Enviar cambios"},
    {"time": "2023-10-01T17:10:00+0200", "source": "Cancel the operation", "input": "Cancelar la operación"},
    {"time": "2023-10-01T15:55:00Z", "source": "Save file as", "input": "Guardar archivo como"}
]

with open(os.path.join(home_dir, "activity.json"), "w") as f:
    json.dump(activity_data, f, indent=2)
EOF

    python3 /tmp/setup.py
    chmod -R 777 /home/user
