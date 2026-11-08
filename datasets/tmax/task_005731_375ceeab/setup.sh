#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app_config

    printf "auth_enabled: true" > /home/user/app_config/auth.yaml
    printf "db_host: localhost\ndb_port: 5432" > /home/user/app_config/db.yaml
    printf "queue_size: 100" > /home/user/app_config/queue.conf
    printf "just some notes" > /home/user/app_config/notes.txt

    cat << 'EOF' > /home/user/deploy.log
[DEPLOY_START]
ID: 1040
Status: SUCCESS
Files:
 - /home/user/app_config/auth.yaml (sha256: 14227f4d4ce2562276527b13493e8e2eb0b4b2382cf4f145452d3a3721054a10)
 - /home/user/app_config/db.yaml (sha256: dummydbhash1234567890abcdef1234567890abcdef1234567890abcdef12345)
 - /home/user/app_config/old_api.conf (sha256: dummyapihash1234567890abcdef1234567890abcdef1234567890abcdef12345)
[DEPLOY_END]
[DEPLOY_START]
ID: 1041
Status: FAILED
Files:
 - /home/user/app_config/auth.yaml (sha256: 14227f4d4ce2562276527b13493e8e2eb0b4b2382cf4f145452d3a3721054a10)
 - /home/user/app_config/db.yaml (sha256: 9f2b8a0ebc8588fdfb55a9b9b00862088f1dcabf1b8a5fcbd7607a68e0dcf454)
 - /home/user/app_config/queue.conf (sha256: 32bfbfda5eb0dfba3de5b642e03884cb4076e07c87cde12cf5a1a15320c279a9)
[DEPLOY_END]
EOF

    chmod -R 777 /home/user
