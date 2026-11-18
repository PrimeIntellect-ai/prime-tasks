#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/nodes.csv
node_id,profile_data
N_01,"{""age"": 25, ""country"": ""USA""}"
N_02,"{""age"": 30, ""country"": ""UK""}"
N_42,"{""age"": 40, ""country"": ""CA""}"
N_99,"{""age"": 22, ""country"": ""AU""}"
EOF

    cat << 'EOF' > /home/user/data/edges.csv
source,target,interaction_type
N_01,N_42,like
N_02,N_42,comment
N_42,N_99,like
EOF

    mkdir -p /app
    convert -background white -fill black -pointsize 36 label:"Target Node: N_42\nDepth: 1" /app/query_params.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
