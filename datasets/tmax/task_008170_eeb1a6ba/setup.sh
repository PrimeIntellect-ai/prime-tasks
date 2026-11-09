#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/datasets

    cat << 'EOF' > /home/user/datasets/ds1.json
{
  "id": "d1",
  "name": "NLP Corpus A",
  "tags": ["nlp", "text", "classification"]
}
EOF

    cat << 'EOF' > /home/user/datasets/ds2.json
{
  "id": "d2",
  "name": "NLP Corpus B",
  "tags": ["nlp", "text", "generation"]
}
EOF

    cat << 'EOF' > /home/user/datasets/ds3.json
{
  "id": "d3",
  "name": "Vision Dataset",
  "tags": ["vision", "image", "classification"]
}
EOF

    cat << 'EOF' > /home/user/datasets/ds4_invalid.json
{
  "id": "d4",
  "name": "Missing Tags Dataset"
}
EOF

    cat << 'EOF' > /home/user/datasets/ds5.json
{
  "id": "d5",
  "name": "Object Detection",
  "tags": ["vision", "object-detection"]
}
EOF

    cat << 'EOF' > /home/user/datasets/ds6_invalid.json
{
  "id": "d6",
  "name": "Empty Tags",
  "tags": []
}
EOF

    chown -R user:user /home/user/datasets
    chmod -R 777 /home/user
