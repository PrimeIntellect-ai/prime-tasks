#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/nodes.csv
id,type,name
srv_auth,Service,Authenticator
srv_db,Service,MainDB
srv_cache,Service,RedisCache
srv_queue,Service,RabbitMQ
srv_ui,Frontend,UserInterface
EOF

    cat << 'EOF' > /home/user/edges.csv
source_id,target_id,relationship
srv_auth,srv_db,DEPENDS_ON
srv_auth,srv_cache,DEPENDS_ON
srv_queue,srv_db,DEPENDS_ON
srv_ui,srv_auth,CALLS
EOF

    chmod -R 777 /home/user
