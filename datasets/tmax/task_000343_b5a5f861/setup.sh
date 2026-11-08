#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas networkx

    mkdir -p /home/user

    cat << 'EOF' > /home/user/nodes.csv
id,name,department
E001,Alice,Executive
E002,Bob,Engineering
E003,Charlie,Engineering
E004,Dave,Engineering
E005,Eve,Engineering
E006,Frank,Sales
E007,Grace,Sales
EOF

    cat << 'EOF' > /home/user/edges.csv
source,target,relation_type
E002,E001,reports_to
E003,E002,reports_to
E004,E003,reports_to
E005,E003,reports_to
E006,E001,reports_to
E007,E006,reports_to
E004,E005,colleague
E003,E001,friend
E007,E002,friend
E001,E002,colleague
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
