#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/nodes.csv
node_id,node_type,name
N1,Employee,Intern_Bob
N2,Role,Intern_Role
N3,Role,Junior_Dev_Role
N4,Role,Dev_Ops_Role
N5,System,Dev_Server
N6,System,Financial_DB_Prod
N7,Employee,Admin_Alice
N8,Role,Admin_Role
N9,Employee,Standard_User
EOF

    cat << 'EOF' > /home/user/edges.csv
source_id,target_id,edge_type
N1,N2,HAS_ROLE
N7,N8,HAS_ROLE
N9,N2,HAS_ROLE
N2,N3,ROLE_INHERITS
N3,N5,CAN_ACCESS
N3,N4,ROLE_INHERITS
N4,N6,CAN_ACCESS
N8,N6,CAN_ACCESS
N8,N5,CAN_ACCESS
EOF

    chmod -R 777 /home/user
