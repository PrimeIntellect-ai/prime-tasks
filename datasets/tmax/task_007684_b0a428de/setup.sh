#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/graph_data.csv
subject,predicate,object
Alice,works_for,TechCorp
ProductX,produced_by,TechCorp
Bob,purchased,ProductX
Alice,works_for,GloboChem
ProductY,produced_by,GloboChem
Dave,purchased,ProductY
Eve,works_for,TechCorp
ProductW,produced_by,TechCorp
Bob,purchased,ProductW
Alice,works_for,Initech
ProductZ,produced_by,Initech
Bob,purchased,ProductZ
Charlie,works_for,MassiveDynamic
ProductA,produced_by,MassiveDynamic
Alice,purchased,ProductA
Bob,works_for,Initech
ProductB,produced_by,Initech
Alice,purchased,ProductB
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
