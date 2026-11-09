#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/translations

    cat << 'EOF' > /home/user/translations/en.csv
key,text
greeting,Hello
farewell,Goodbye
apple,Apple
EOF

    cat << 'EOF' > /home/user/translations/fr.csv
key,text
greeting,Bonjour
farewell,Au revoir
EOF

    cat << 'EOF' > /home/user/translations/ja.csv
key,text
greeting,こんにちは
apple,りんご
EOF

    cat << 'EOF' > /home/user/translations/es.csv
key,text
greeting,Hola
farewell,Adiós
apple,Manzana
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
