#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    bash -c '
    mkdir -p /home/user/config_backups /home/user/extracted_configs /home/user/organized_configs
    cd /home/user/config_backups
    mkdir -p temp_configs
    for i in $(seq -w 1 100); do
      YEAR=$(( 2020 + (10#$i % 4) ))
      MONTH=$(printf "%02d" $(( (10#$i % 12) + 1 )))
      DAY=$(printf "%02d" $(( (10#$i % 28) + 1 )))

      cat <<EOF > temp_configs/server_$i.conf
SERVER_ID=server_$i
BIND_IP=10.0.0.$((10#$i))
API_ENDPOINT=http://old.internal/api
TIMESTAMP=$YEAR-$MONTH-$DAY
EOF
    done
    cd temp_configs
    tar -czf ../legacy_configs.tar.gz *.conf
    cd ..
    rm -rf temp_configs
    '

    chmod -R 777 /home/user
