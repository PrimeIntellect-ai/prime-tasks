#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/reviews_part1.csv
review_id,product_id,text,timestamp
r1,p1,This is great! 👍,2023-01-02T10:00:00Z
r2,p2,Café is nice,2023-01-01T12:00:00Z
r3,p1,this is great! 👍,2023-01-01T09:00:00Z
r4,p3,  Very   good. ,2023-01-03T15:00:00Z
EOF

    cat << 'EOF' > /home/user/reviews_part2.json
[
    {"review_id": "r5", "product_id": "p2", "text": "CAFÉ IS NICE", "timestamp": "2023-01-02T11:00:00Z"},
    {"review_id": "r6", "product_id": "p3", "text": "こんにちは", "timestamp": "2023-01-04T08:00:00Z"},
    {"review_id": "r7", "product_id": "p4", "text": "A B C D E", "timestamp": "2023-01-05T10:00:00Z"},
    {"review_id": "r8", "product_id": "p1", "text": "Another review here!!", "timestamp": "2023-01-06T10:00:00Z"}
]
EOF

    chmod -R 777 /home/user
