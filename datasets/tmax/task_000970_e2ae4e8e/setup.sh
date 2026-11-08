#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_translations.jsonl
{"term": "save", "es": "guardar", "fr": "sauvegarder", "de": "speichern\u00"}
{"term": "open", "es": " abrir ", "fr": "ouvrir", "de": "öffnen"}
{"term": "exit", "es": "salir\uZZZZ", "fr": "quitter", "de": "beenden"}
{"term": "apple", "es": "manzana", "fr": "pomme", "de": "Apfel"}
EOF

    cat << 'EOF' > /home/user/categories.csv
term,category
save,menu
open,menu
exit,menu
apple,food
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
