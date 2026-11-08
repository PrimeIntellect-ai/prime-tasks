#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/locales
    cat << 'EOF' > /home/user/locales/app_strings.json
[
  {"key": "greeting", "language": "en", "translation": "Hello"},
  {"key": "greeting", "language": "es", "translation": "Hola"},
  {"key": "farewell", "language": "en", "translation": "Goodbye"},
  {"key": "submit", "language": "en", "translation": "Submit"},
  {"key": "submit", "language": "de", "translation": "Einreichen"}
]
EOF

    cat << 'EOF' > /home/user/locales/web_strings.csv
key,en,es,fr,de
greeting,Hi,Hola Web,Bonjour,Hallo
login,Log In,Iniciar,Connexion,Anmelden
submit,Send,,Envoyer,
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
