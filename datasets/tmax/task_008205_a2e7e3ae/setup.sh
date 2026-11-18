#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y --no-install-recommends python3 python3-pip cargo sqlite3
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_data.jsonl
{"id": "1", "category": "electronics", "product_name": "TV", "review_text": "Tr\\u00e8s bien!"}
{"id": "2", "category": "books", "product_name": "Rust Guide", "review_text": "Great\\u2014book"}
{"id": "3", "category": "electronics", "product_name": "Radio", "review_text": "It is ok."}
{"id": "4", "category": "apparel", "product_name": "T-Shirt", "review_text": "C\\'est g\\u00e9nial"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
