#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/locales.csv
id,timestamp,lang,text
1,2023/10/05-14:30:00,es,"Hola,
mundo"
2,2023/10/06-09:15:00,fr,"Bonjour le monde"
3,2023/10/07-11:00:22,de,"Das ist ein ""Test""
mit
neuen Zeilen"
EOF

    chmod -R 777 /home/user
