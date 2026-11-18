#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk sed coreutils
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_reviews.jsonl
{"id": 1, "user": "John Doe <john.doe@tech-corp.com>", "review": "This is an amazing product! Contact me at 555-9988 for details."}
{"id": 2, "user": "Maria Garcia <mgarcia@domain.es>", "review": "Me encanta esto. 🌟 Mi numero es 123-4567."}
{"id": 3, "user": "Taro Yamada <taro.y@nippon.co.jp>", "review": "素晴らしい製品です！ サポート窓口 987-6543 まで。"}
{"id": 4, "user": "Anonymous <no-reply@hidden.net>", "review": "Just okay. No PII here."}
{"id": 5, "user": "Missing Email", "review": "What happens if I put an email in the review like test@test.com ?"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
