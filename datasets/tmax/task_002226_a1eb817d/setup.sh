#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cron gawk
pip3 install pytest

mkdir -p /home/user/incoming
cd /home/user/incoming

cat << 'EOF' > syslog_eu.utf8
[12/Oct/2023:14:32:10 +0200] INFO: Démarrage du système
[12/Oct/2023:14:35:00 +0200] ERROR: Connexion échouée à la base de données
[12/Oct/2023:14:40:00 +0200] INFO: Traitement terminé
[12/Oct/2023:15:10:22 +0200] ERROR: Fichier introuvable
EOF
iconv -f UTF-8 -t ISO-8859-1 syslog_eu.utf8 > syslog_eu.log
rm syslog_eu.utf8

cat << 'EOF' > app_asia.utf8
2023-10-12 21:40:00 JST - OK - 起動完了
2023-10-12 21:45:00 JST - FAIL - 致命的なエラーが発生しました
2023-10-12 21:50:00 JST - OK - 同期成功
2023-10-12 22:15:30 JST - FAIL - タイムアウト例外
EOF
iconv -f UTF-8 -t UTF-16LE app_asia.utf8 > app_asia.log
rm app_asia.utf8

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
