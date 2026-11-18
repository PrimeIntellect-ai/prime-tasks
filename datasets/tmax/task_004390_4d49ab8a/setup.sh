#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_translations.csv
timestamp,translator_id,lang_code,translation_key,translated_text
2023-10-01T12:00:00Z,101,EN-US,greeting,Hello
2023-10-01T12:05:00Z,102,fr-fr,greeting,Bonjour
2023-10-01T12:10:00Z,101,en-us,greeting,Hello!
2023-10-01T13:00:00Z,abc,es-es,greeting,Hola
2023-10-01T13:05:00Z,103,es-es,,Hola
2023-10-01T13:10:00Z,104,IT-IT,greeting,Ciao
2023-10-01T14:00:00Z,105,ja-jp,farewell,Sayonara
2023-10-01T15:00:00Z,101,en-us,farewell,Goodbye
2023-10-01T15:30:00Z,102,fr-fr,farewell,Au revoir
invalid-time,101,en-us,test,Test
2023-10-02T10:00:00Z,101,EN-US,farewell,Bye!
EOF

    chmod -R 777 /home/user
