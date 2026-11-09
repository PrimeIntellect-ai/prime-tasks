#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest pandas pyarrow

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/loc_drops

    cat << 'EOF' > /home/user/loc_drops/drop_1.jsonl
{"timestamp": "2023-11-01T10:00:00Z", "lang": "fr-FR", "key": "welcome", "value": "Bienvenue"}
{"timestamp": "2023-11-01T10:05:00Z", "lang": "fr-FR", "key": "error_msg", "value": "Erreur \uZZZZ !\n"}
{"timestamp": "2023-11-01T10:10:00Z", "lang": "es-ES", "key": "welcome", "value": "Hola \u0021"}
EOF

    cat << 'EOF' > /home/user/loc_drops/drop_2.jsonl
{"timestamp": "2023-11-02T10:00:00Z", "lang": "fr-FR", "key": "logout", "value": "Déconnexion"}
{"timestamp": "2023-11-02T10:05:00Z", "lang": "es-ES", "key": "logout", "value": "Salir \u12XY"}
EOF

    chmod -R 777 /home/user
