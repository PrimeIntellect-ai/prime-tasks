#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data/input/
    mkdir -p /home/user/data/output/

    cat << 'EOF' > /home/user/data/input/feedback1.csv
id,timestamp,comments
101,2023-10-01T10:00:00Z,"This is a great
product!  "
102,2023-10-01T10:05:00Z,"Terrible,   would not buy again."
103,2023-10-01T10:15:00Z,"This is a great product!"
EOF

    cat << 'EOF' > /home/user/data/input/feedback2.json
[
  {"id": 201, "timestamp": "2023-10-01T09:00:00Z", "comments": "this IS a great\tproduct!"},
  {"id": 202, "timestamp": "2023-10-01T11:00:00Z", "comments": "Needs improvement."}
]
EOF

    chown -R user:user /home/user/data
    chmod -R 777 /home/user
