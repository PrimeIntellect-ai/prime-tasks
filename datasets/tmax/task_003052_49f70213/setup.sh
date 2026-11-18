#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/interactions.csv
Albuterol,Drug,targets,ADRB2,Gene
ADRB2,Gene,associated_with,Asthma,Disease
Fluticasone,Drug,targets,NR3C1,Gene
NR3C1,Gene,associated_with,Asthma,Disease
Ibuprofen,Drug,targets,PTGS2,Gene
PTGS2,Gene,associated_with,Headache,Disease
Omalizumab,Drug,targets,IGHE,Gene
IGHE,Gene,associated_with,Asthma,Disease
Metformin,Drug,targets,AMPK,Gene
AMPK,Gene,associated_with,Diabetes,Disease
FakeDrug,Drug,targets,FakeGene,Gene
FakeGene,Gene,interacts_with,Asthma,Disease
EOF

    chmod -R 777 /home/user
