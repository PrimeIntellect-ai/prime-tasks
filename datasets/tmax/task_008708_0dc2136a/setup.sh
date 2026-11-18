#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest rdflib jsonschema

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_papers.json
[
    {"id": "p1", "authors": ["Alice_Smith"], "venue": "Nature", "cites": []},
    {"id": "p2", "authors": ["Bob_Jones"], "venue": "Science", "cites": ["p1"]},
    {"id": "p3", "authors": ["Charlie_Brown"], "venue": "Science", "cites": ["p1"]},
    {"id": "p4", "authors": ["Dave_White"], "venue": "Nature", "cites": ["p1"]},
    {"id": "p6", "authors": ["Eve_Davis"], "venue": "Journal of AI", "cites": []},
    {"id": "p5", "authors": ["Frank_Miller"], "venue": "Science", "cites": ["p6"]},
    {"id": "p7", "authors": ["Grace_Hopper"], "venue": "Science", "cites": ["p6"]},
    {"id": "p8", "authors": ["Heidi_Klum"], "venue": "Science", "cites": ["p6"]},
    {"id": "p10", "authors": ["Ivan_Drago"], "venue": "ArXiv", "cites": []},
    {"id": "p11", "authors": ["Judy_Garland"], "venue": "Science", "cites": ["p10", "p1"]},
    {"id": "p99", "venue": "Science", "cites": ["p1"]}
]
EOF

    cat << 'EOF' > /home/user/input_schema.json
{
    "type": "object",
    "properties": {
        "id": {"type": "string"},
        "authors": {
            "type": "array",
            "items": {"type": "string"},
            "minItems": 1
        },
        "venue": {"type": "string"},
        "cites": {
            "type": "array",
            "items": {"type": "string"}
        }
    },
    "required": ["id", "authors", "venue", "cites"]
}
EOF

    cat << 'EOF' > /home/user/output_schema.json
{
    "type": "array",
    "items": {
        "type": "object",
        "properties": {
            "author": {"type": "string"},
            "science_citations": {"type": "integer"}
        },
        "required": ["author", "science_citations"]
    },
    "maxItems": 3
}
EOF

    chmod -R 777 /home/user
