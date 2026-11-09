#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/

    cat << 'EOF' > /home/user/tm.csv
source,target
User Profile,Profil de l'utilisateur
Settings,Réglages
Save changes,Enregistrer les modifications
Hello universe,Bonjour l'univers
EOF

    cat << 'EOF' > /home/user/translations.jsonl
{"id": 1, "source": "Hello world", "target": "Bonjour le monde", "confidence": 0.99}
{"id": 2, "source": "User \\u00e9 Profile", "target": "Profil utilisateur", "confidence": null}
{"id": 2, "source": "User \\u00e9 Profile", "target": "Profil utilisateur", "confidence": null}
{"id": 3, "source": "Save changes", "target": "Sauvegarder", "confidence": null}
{"id": 4, "source": "Settings \\u2699", "target": "Param\u00e8tres", "confidence": 0.85}
{"id": 1, "source": "Hello world", "target": "Bonjour le monde", "confidence": 0.995}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
