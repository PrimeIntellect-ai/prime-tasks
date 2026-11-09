#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip rustc cargo
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/raw_translations.csv
timestamp,translator_id,locale,translation_text
2023-10-24T14:15:00Z,user_123,fr_FR,"Bonjour
le monde"
2023-10-24T14:35:22Z,user_456,fr_FR,"Merci beaucoup"
2023-10-24T14:45:00Z,user_789,fr_FR,"Au revoir"
2023-10-24T14:10:00Z,user_111,es_ES,"Hola"
2023-10-24T15:05:00Z,user_123,es_ES,"Hola
Amigo"
2023-10-24T15:10:00Z,user_222,es_ES,"Adiós"
2023-10-24T15:15:00Z,user_333,es_ES,"Buenos días"
2023-10-25T09:01:00Z,user_999,de_DE,"Guten
Morgen"
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
