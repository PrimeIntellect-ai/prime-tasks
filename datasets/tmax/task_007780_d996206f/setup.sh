#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/translations.csv
1700000000,es_ES,id1,"Hola"
1700001000,es_ES,id2,"Linea Uno
Linea Dos"
1700001500,fr_FR,id2,"Ignorer
Moi"
1700003000,es_ES,id3,""
1700004000,es_ES,id4,"Salto


Texto"
1700005000,es_ES,id5,"Mas texto con numeros 12345"
1700007600,es_ES,id6,"Ultima
linea"
EOF

    chmod -R 777 /home/user
