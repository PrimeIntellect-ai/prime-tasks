#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.jsonl
{"user_id": 101, "ad_id": 501, "clicks": 5, "impressions": 100, "timestamp": "2023-10-15T08:30:00Z"}
{"user_id": 102, "ad_id": 502, "clicks": "2", "impressions": 50, "timestamp": "2023-10-15T09:15:00Z"}
{"user_id": 103, "ad_id": 503, "clicks": 10, "impressions": 5, "timestamp": "2023-10-15T14:00:00Z"}
{"user_id": 104, "ad_id": 504, "clicks": 0, "impressions": 20, "timestamp": "2023-10-15T22:45:00Z"}
{"user_id": 105, "ad_id": 505, "clicks": 1, "impressions": 10, "timestamp": "2023-10-16T00:05:00Z"}
{"user_id": 101, "ad_id": 506, "clicks": -1, "impressions": 10, "timestamp": "2023-10-15T08:30:00Z"}
{"user_id": 106, "ad_id": 507, "clicks": 2, "impressions": 0, "timestamp": "2023-10-15T11:00:00Z"}
{"user_id": 107, "ad_id": 508, "clicks": 3, "impressions": 50}
{"user_id": 108, "ad_id": 509, "clicks": 15, "impressions": 1000, "timestamp": "2023-10-15T18:22:00Z", "extra_field": true}
{"user_id": 109, "ad_id": 510, "clicks": 15, "impressions": 1000, "timestamp": "2023-10-15T18:22:00Z"}
EOF

    chmod -R 777 /home/user
