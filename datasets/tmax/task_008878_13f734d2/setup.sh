#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/app_data/logs
mkdir -p /home/user/app_data/config
mkdir -p /home/user/app_data/cache
mkdir -p /home/user/app_data/temp_exclude

cat << 'EOF' > /home/user/backup_rules.json
{"include_extensions": [".json", ".xml", ".csv"], "exclude_dirs": ["temp_exclude", "cache"]}
EOF

cat << 'EOF' > /home/user/state.json
{"last_run": 1600000000}
EOF

touch /home/user/app_data/logs/app.json && touch -d @1600000100 /home/user/app_data/logs/app.json
touch /home/user/app_data/logs/old.json && touch -d @1599999900 /home/user/app_data/logs/old.json
touch /home/user/app_data/logs/data.csv && touch -d @1600000500 /home/user/app_data/logs/data.csv
touch /home/user/app_data/logs/readme.txt && touch -d @1600000500 /home/user/app_data/logs/readme.txt
touch /home/user/app_data/config/settings.xml && touch -d @1600000200 /home/user/app_data/config/settings.xml
touch /home/user/app_data/temp_exclude/hidden.json && touch -d @1600001000 /home/user/app_data/temp_exclude/hidden.json
touch /home/user/app_data/cache/data.xml && touch -d @1600001000 /home/user/app_data/cache/data.xml

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
