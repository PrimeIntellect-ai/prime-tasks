#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/datasets/concepts

    cat << 'EOF' > /home/user/datasets/concepts/c1.json
{
  "id": "c1",
  "name": "Quantum Computing",
  "depends_on": ["c2", "c3"],
  "related_to": ["c8"]
}
EOF

    cat << 'EOF' > /home/user/datasets/concepts/c2.json
{
  "id": "c2",
  "name": "Quantum Mechanics",
  "depends_on": ["c4"],
  "related_to": ["c3"]
}
EOF

    cat << 'EOF' > /home/user/datasets/concepts/c3.json
{
  "id": "c3",
  "name": "Linear Algebra",
  "depends_on": ["c5", "c6"],
  "related_to": ["c4"]
}
EOF

    cat << 'EOF' > /home/user/datasets/concepts/c4.json
{
  "id": "c4",
  "name": "Physics",
  "depends_on": [],
  "related_to": ["c2"]
}
EOF

    cat << 'EOF' > /home/user/datasets/concepts/c5.json
{
  "id": "c5",
  "name": "Mathematics",
  "depends_on": [],
  "related_to": []
}
EOF

    cat << 'EOF' > /home/user/datasets/concepts/c6.json
{
  "id": "c6",
  "name": "Matrix Theory",
  "depends_on": ["c5"],
  "related_to": []
}
EOF

    cat << 'EOF' > /home/user/datasets/concepts/c7.json
{
  "id": "c7",
  "name": "String Theory",
  "depends_on": ["c4"],
  "related_to": []
}
EOF

    cat << 'EOF' > /home/user/datasets/concepts/c8.json
{
  "id": "c8",
  "name": "Graph Theory",
  "depends_on": ["c5"],
  "related_to": []
}
EOF

    cat << 'EOF' > /home/user/datasets/concepts/c9.json
{
  "id": "c9",
  "name": "Topology",
  "depends_on": ["c5"],
  "related_to": ["c10"]
}
EOF

    cat << 'EOF' > /home/user/datasets/concepts/c10.json
{
  "id": "c10",
  "name": "Geometry",
  "depends_on": ["c5"],
  "related_to": ["c11"]
}
EOF

    cat << 'EOF' > /home/user/datasets/concepts/c11.json
{
  "id": "c11",
  "name": "Manifolds",
  "depends_on": ["c9", "c10"],
  "related_to": ["c9"]
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
