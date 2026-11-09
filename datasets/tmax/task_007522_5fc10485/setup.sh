#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/access_log.csv
user_id,role,resource
101,admin,PROD_DB
102,viewer,PROD_DB
103,editor,STAGING_DB
104,admin,PROD_DB
105,viewer,PROD_DB
106,guest,DEV_DB
107,admin,PROD_DB
108,viewer,PROD_DB
109,editor,PROD_DB
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
