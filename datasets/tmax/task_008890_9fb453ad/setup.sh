#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/raw_data

    cat << 'EOF' > /home/user/raw_data/batch_0.jsonl
{"id": "A10", "category": "tech", "text": "This is a great laptop!! I love it."}
{"id": "B01", "category": "home", "text": "Very bad."}
{"id": "C05", "category": "sports", "text": "The ball is too small, bouncing weirdly."}
{"id": "A02", "category": "tech", "text": "Screen broke after 2 days..."}
{"id": "B02", "category": "home", "text": "Vacuum works fine, but loud"}
{"id": "C01", "category": "sports", "text": "Ok"}
EOF

    cat << 'EOF' > /home/user/raw_data/batch_1.jsonl
{"id": "A03", "category": "tech", "text": "Battery life is amazing! 10/10"}
{"id": "B03", "category": "home", "text": "Couch is soft and comfortable. Good buy."}
{"id": "C02", "category": "sports", "text": "Bat broke on first hit!"}
{"id": "A04", "category": "tech", "text": "Mouse wheel is sticky."}
{"id": "B04", "category": "home", "text": "Table arrived scratched. Support was unhelpful."}
{"id": "C03", "category": "sports", "text": "Great grip on these gloves."}
EOF

    cat << 'EOF' > /home/user/raw_data/batch_2.jsonl
{"id": "A05", "category": "tech", "text": "Wifi drops constantly."}
{"id": "B05", "category": "home", "text": "Lamp is too dim for reading."}
{"id": "C04", "category": "sports", "text": "Helmet fits perfectly, highly recommend."}
{"id": "A06", "category": "tech", "text": "Keyboard feels mushy to type on"}
{"id": "B06", "category": "home", "text": "Rug colors don't match the picture"}
{"id": "C06", "category": "sports", "text": "Cleats are too narrow"}
EOF

    cat << 'EOF' > /home/user/raw_data/batch_3.jsonl
{"id": "A07", "category": "tech", "text": "Good monitor for the price."}
{"id": "B07", "category": "home", "text": "Blender smells like burning rubber..."}
{"id": "C07", "category": "sports", "text": "Tennis racket strings snapped."}
{"id": "A08", "category": "tech", "text": "GPU runs very hot."}
{"id": "B08", "category": "home", "text": "Towels are very fluffy."}
{"id": "C08", "category": "sports", "text": "Golf clubs are lightweight."}
{"id": "A09", "category": "tech", "text": "It works."}
EOF

    chmod -R 777 /home/user
