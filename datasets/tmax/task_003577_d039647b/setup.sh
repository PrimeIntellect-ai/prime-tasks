#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/papers.jsonl
{"id": "p1", "authors": ["Alice"], "references": [], "topics": ["AI", "Graph"]}
{"id": "p2", "authors": ["Bob"], "references": ["p1"], "topics": ["AI", "ML"]}
{"id": "p3", "authors": ["Charlie"], "references": ["p1"], "topics": ["Graph", "Data"]}
{"id": "p4", "authors": ["Dave"], "references": ["p1"], "topics": ["AI"]}
{"id": "p5", "authors": ["Eve"], "references": ["p2"], "topics": ["ML"]}
{"id": "p6", "authors": ["Frank"], "references": ["p3"], "topics": ["Data"]}
{"id": "p7", "authors": ["Grace"], "references": ["p4"], "topics": ["AI"]}
{"id": "p8", "authors": ["Heidi"], "references": ["p7"], "topics": ["AI", "Ethics"]}
{"id": "p9", "authors": ["Ivan"], "references": ["p8"], "topics": ["Robotics"]}
{"id": "p10", "authors": ["Judy"], "references": ["p8"], "topics": ["Robotics", "Ethics"]}
{"id": "p11", "authors": ["Mallory"], "references": ["p8"], "topics": ["Ethics"]}
{"id": "p12", "authors": ["Niaj"], "references": ["p9", "p10"], "topics": ["Robotics"]}
{"id": "p13", "authors": ["Olivia"], "references": ["p11"], "topics": ["Ethics", "Law"]}
EOF

    chmod -R 777 /home/user
