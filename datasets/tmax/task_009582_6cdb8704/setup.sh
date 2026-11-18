#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data/feedback
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/feedback/batch1.csv
id,product_category,rating,feedback_text
1,electronics,5,"Great product"
2,home,3,"Okay, but
has a scratch on the side
still works though"
3,electronics,4,"Works well
Very happy"
4,garden,2,"Broke on first use"
EOF

    cat << 'EOF' > /home/user/data/feedback/batch2.json
[
  {"id": 5, "product_category": "home", "rating": 4, "feedback_text": "Nice"},
  {"id": 6, "product_category": "toys", "rating": 5, "feedback_text": "Kids love it"},
  {"id": 7, "product_category": "garden", "rating": 4, "feedback_text": "Good value"}
]
EOF

    cat << 'EOF' > /home/user/data/feedback/batch3.csv
id,product_category,rating,feedback_text
8,toys,4,"Fun"
9,electronics,2,"Not as described
Returning it tomorrow."
EOF

    chown -R user:user /home/user/data
    chown -R user:user /home/user/output
    chmod -R 777 /home/user
