#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_data.py
import json
import os

os.makedirs("/home/user", exist_ok=True)

data = [
    # Rejected lines
    {"ts": 100, "lang": "ENG", "mod": "auth", "id": "btn_1", "old": "Login", "new": "Log In"}, # invalid lang
    {"ts": 101, "lang": "fr", "mod": "auth", "id": "btn_2", "old": "Save", "new": ""}, # empty new
    {"ts": 102, "lang": "es", "mod": "auth", "id": "btn_3", "old": "Cancel", "new": "Cancel"}, # identical

    # Valid lines - Group: fr, auth
    {"ts": 200, "lang": "fr", "mod": "auth", "id": "fr_auth_1", "old": "Hi", "new": "Bonjour"}, # R = 7/3 = 2.333. RA = 2.333
    {"ts": 201, "lang": "fr", "mod": "auth", "id": "fr_auth_2", "old": "OK", "new": "D'accord"}, # R = 8/3 = 2.666. RA = 2.5
    {"ts": 202, "lang": "fr", "mod": "auth", "id": "fr_auth_3", "old": "No", "new": "Non"}, # R = 3/3 = 1.0. RA = 1.999
    {"ts": 203, "lang": "fr", "mod": "auth", "id": "fr_auth_4", "old": "Yes", "new": "Oui"}, # R = 3/4 = 0.75. RA = 1.6875
    {"ts": 204, "lang": "fr", "mod": "auth", "id": "fr_auth_5", "old": "A", "new": "Ceci est une traduction tres longue et inutile"}, # R = 46/2 = 23.0. RA = 5.95 -> FLAG!
    {"ts": 205, "lang": "fr", "mod": "auth", "id": "fr_auth_6", "old": "Back", "new": "Retour"}, # R = 6/5 = 1.2. (Drop 2.333) RA = (2.666+1.0+0.75+23.0+1.2)/5 = 5.72 -> FLAG!

    # Valid lines - Group: es, nav
    {"ts": 150, "lang": "es", "mod": "nav", "id": "es_nav_1", "old": "Home", "new": "Inicio"}, # R = 6/5 = 1.2
    {"ts": 151, "lang": "es", "mod": "nav", "id": "es_nav_2", "old": "Menu", "new": "Menú"}, # R = 5/5 = 1.0
]

with open("/home/user/loc_updates.jsonl", "w") as f:
    for d in data:
        f.write(json.dumps(d) + "\n")
EOF

    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
