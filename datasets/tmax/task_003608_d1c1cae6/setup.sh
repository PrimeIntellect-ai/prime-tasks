#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/app_data/nested

cat << 'EOF' > /home/user/app_data/old_data.csv
id,name,value
1,alpha,100
EOF

cat << 'EOF' > /home/user/app_data/old_config.xml
<records><record><id>2</id><name>beta</name><value>200</value></record></records>
EOF

cat << 'EOF' > /home/user/app_data/new_data.csv
id,name,value
3,gamma,300
EOF

cat << 'EOF' > /home/user/app_data/nested/new_config.xml
<records><record><id>4</id><name>delta</name><value>400</value></record></records>
EOF

cat << 'EOF' > /home/user/app_data/new_settings.json
[{"id": "5", "name": "epsilon", "value": "500"}]
EOF

touch -t 202201010000 /home/user/app_data/old_data.csv
touch -t 202201010000 /home/user/app_data/old_config.xml
touch -t 202301010000 /home/user/last_backup.stamp
touch -t 202401010000 /home/user/app_data/new_data.csv
touch -t 202401010000 /home/user/app_data/nested/new_config.xml
touch -t 202401010000 /home/user/app_data/new_settings.json

chmod -R 777 /home/user
