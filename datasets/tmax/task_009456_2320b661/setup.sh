#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go gcc libc6-dev sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_translations.csv
timestamp,lang_code,translation_key,original_text,translated_text
1620000000,fr,welcome_msg,Welcome {user}!,Bienvenue {user}!
1620000005,fr,goodbye,Goodbye!,Au revoir!
1620000010,es-ES,welcome_msg,Welcome {user}!,Bienvenido {user}!
1620000015,fr,invalid-key,Hello,Bonjour
1620000020,de,welcome_msg,Welcome {user}!,Willkommen {name}!
1620000025,fr,welcome_msg,Welcome {user}!,Bienvenue cher {user}!
1620000030,BAD,test,test,test
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
