#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/edges.csv
source,target,type
u_charlie,r_admin,HAS_ROLE
r_admin,g_wheel,IN_GROUP
g_wheel,res_db_main,CAN_ACCESS
g_wheel,g_ops,IN_GROUP
g_ops,g_wheel,IN_GROUP
g_ops,res_server_1,CAN_ACCESS
u_charlie,g_ops,IN_GROUP
u_bob,r_viewer,HAS_ROLE
r_viewer,res_dashboard,CAN_ACCESS
u_alice,g_ops,IN_GROUP
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
