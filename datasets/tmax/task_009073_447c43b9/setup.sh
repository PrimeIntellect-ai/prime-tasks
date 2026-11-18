#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/tm.json
[
  {"source": "hello world", "target": "hola mundo"},
  {"source": "save file", "target": "guardar archivo"},
  {"source": "delete item", "target": "eliminar elemento"},
  {"source": "user profile", "target": "perfil de usuario"}
]
EOF

    cat << 'EOF' > /home/user/new_strings.txt
  Hello World
Save  File
delete items
hello world
User Profiles
Save Game
EOF

    chmod -R 777 /home/user
