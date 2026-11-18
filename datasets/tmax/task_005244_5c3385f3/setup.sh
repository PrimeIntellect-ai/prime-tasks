#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --no-cache-dir pytest pandas scikit-learn

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/documents.json
[
  {"id": 1, "text": "machine learning is fascinating", "label": 1},
  {"id": 2, "text": "artificial intelligence models", "label": 1},
  {"id": 3, "text": "the weather is nice today", "label": 0},
  {"id": 4, "text": "deep learning neural networks", "label": 1},
  {"id": 5, "text": "i like to eat apples", "label": 0},
  {"id": 6, "text": "data science and predictive modeling", "label": 1},
  {"id": 7, "text": "going for a walk outside", "label": 0},
  {"id": 8, "text": "support vector machines in python", "label": 1},
  {"id": 9, "text": "cooking dinner in the kitchen", "label": 0},
  {"id": 10, "text": "gradient boosting trees", "label": 1}
]
EOF

    cat << 'EOF' > /home/user/data/metadata.csv
id,category_id
1,10
2,10
3,20
4,10
5,
6,10
7,20
8,10
9,20
10,
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
