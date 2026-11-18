#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_feedback.csv
user_id,2023-11-01,2023-11-03,2023-11-04
u1,"Great service!","Bad, bad...","Great service!"
u2,"","Okay.",""
u3,"Could be better!!!",,"100% awesome"
EOF

    chmod -R 777 /home/user
