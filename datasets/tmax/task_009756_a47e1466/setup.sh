#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data/raw_reviews/

    cat << 'EOF' > /home/user/data/raw_reviews/batch1.json
[
  {
    "record_id": "R001",
    "user_id": "U100",
    "timestamp": 1620000000,
    "review_text": "Caf\u00e9 is great!"
  },
  {
    "record_id": "R002",
    "user_id": "U100",
    "timestamp": 1620000050,
    "review_text": "Cafe\u0301 is great!"
  },
  {
    "record_id": "R003",
    "user_id": "U101",
    "timestamp": 1620001000,
    "review_text": "The soup was cold."
  }
]
EOF

    cat << 'EOF' > /home/user/data/raw_reviews/batch2.json
[
  {
    "record_id": "R004",
    "user_id": "U101",
    "timestamp": 1620001050,
    "review_text": "The soap was cold."
  },
  {
    "record_id": "R005",
    "user_id": "U102",
    "timestamp": 1620002000,
    "review_text": "\u3053\u3093\u306b\u3061\u306f"
  },
  {
    "record_id": "R006",
    "user_id": "U102",
    "timestamp": 1620002010,
    "review_text": "\u3053\u3093\u3044\u3061\u306f"
  },
  {
    "record_id": "R007",
    "user_id": "U103",
    "timestamp": 1620003000,
    "review_text": "Perfect experience."
  }
]
EOF

    chmod -R 777 /home/user
