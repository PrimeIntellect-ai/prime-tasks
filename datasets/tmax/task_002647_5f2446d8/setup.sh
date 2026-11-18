#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip docker.io jq curl
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/graph_setup.cypher
CREATE (p1:Paper {id: 'P1'}),
       (p2:Paper {id: 'P2'}),
       (p3:Paper {id: 'P3'}),
       (p4:Paper {id: 'P4'}),
       (p5:Paper {id: 'P5'}),
       (p6:Paper {id: 'P6'}),
       (p7:Paper {id: 'P7'}),
       (p8:Paper {id: 'P8'})
CREATE (p1)-[:CITES]->(p2),
       (p1)-[:CITES]->(p3),
       (p2)-[:CITES]->(p4),
       (p3)-[:CITES]->(p4),
       (p3)-[:CITES]->(p5),
       (p4)-[:CITES]->(p6),
       (p6)-[:CITES]->(p7),
       (p5)-[:CITES]->(p8)
EOF
    chmod +r /home/user/graph_setup.cypher

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
