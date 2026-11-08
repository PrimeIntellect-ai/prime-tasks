#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go espeak ffmpeg
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/translations_dump.csv
timestamp,locale,key,translation
1700000000,en,greeting,Hello
1700000100,en,greeting,Hello!
1700000200,en,greeting,Welcome
1700000000,es,greeting,Hola
1700000000,ENG,greeting,Hello
1700000000,fr,farewell,Au revoir
1700000150,fr,farewell,Adieu
EOF

    espeak -w /app/override.wav "fr colon greeting colon salut"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
