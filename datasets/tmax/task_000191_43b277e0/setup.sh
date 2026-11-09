#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/locales/incoming
    mkdir -p /home/user/locales/processed
    mkdir -p /home/user/scripts

    cat << 'EOF' > /home/user/locales/incoming/en_to_fr.txt
[2023/09/28-14:32] greeting_fr := "Bonjour"
[2023/10/05-09:15] farewell_fr := "Au revoir"
This is a malformed line that should be ignored
[2023/10/06-10:00] error_404_fr := "Non trouvé"
[2023/10/01-00:00] midnight_fr := "Minuit"
EOF

    cat << 'EOF' > /home/user/locales/incoming/en_to_es.txt
[2023/10/02-08:00] greeting_es := "Hola"
[2023/10/01-00:01] button_save_es := "Guardar"
[2023/08/12-11:11] old_key_es := "Viejo"
[2024/01/01-00:00] new_year_es := "Feliz Año"
Some other random text
EOF

    chown -R user:user /home/user/locales /home/user/scripts
    chmod -R 777 /home/user
