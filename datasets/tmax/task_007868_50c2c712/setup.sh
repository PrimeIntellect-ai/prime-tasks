#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/datasets

    cat << 'EOF' > /home/user/datasets/researchers.csv
researcher_id,name,project_id
R1,Alice,P1
R2,Bob,P2
R3,Charlie,P1
EOF

    cat << 'EOF' > /home/user/datasets/projects.json
[
  {"project_id": "P1", "title": "AI Research", "publications": ["PUB1", "PUB2"]},
  {"project_id": "P2", "title": "DB Systems", "publications": ["PUB3", "PUB4"]}
]
EOF

    cat << 'EOF' > /home/user/datasets/citations.csv
citing_pub_id,cited_pub_id
PUB1,PUB2
PUB2,PUB1
PUB1,PUB3
PUB3,PUB4
PUB4,PUB3
PUB4,PUB1
PUB2,PUB4
EOF

    chmod -R 777 /home/user
