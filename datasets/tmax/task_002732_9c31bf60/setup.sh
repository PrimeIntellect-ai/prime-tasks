#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_expressions.csv
id,expression
101," 15   x 3 "
102," 100 div   4 "
103,"  7 plus 8"
104,"50   minus 10"
105," 12 x 12 "
106," 9 div 3 "
107,"100 plus 200 "
108," 200 minus 50 "
EOF

    cat << 'EOF' > /home/user/metadata.json
[
  {"id": 101, "category": "Algebra", "author": "Alice"},
  {"id": 102, "category": "Algebra", "author": "Bob"},
  {"id": 103, "category": "Algebra", "author": "Charlie"},
  {"id": 104, "category": "Geometry", "author": "Alice"},
  {"id": 105, "category": "Geometry", "author": "Dave"},
  {"id": 106, "category": "Geometry", "author": "Eve"},
  {"id": 107, "category": "Algebra", "author": "Frank"},
  {"id": 108, "category": "Geometry", "author": "Grace"}
]
EOF

    chmod -R 777 /home/user
