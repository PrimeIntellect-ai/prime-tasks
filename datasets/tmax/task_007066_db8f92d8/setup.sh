#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/products.jsonl
{"id": 101, "names": {"en-US": "Gaming Mouse", "ja-JP": "ゲーミングマウス"}, "price": 5000, "stock": 10}
{"id": 102, "names": {"en-US": "Keyboard", "ja-JP": "キーボード"}, "price": -1000, "stock": 5}
{"id": 103, "names": {"en-US": "Monitor"}, "price": 15000, "stock": 2}
{"id": 104, "names": {"en-US": "Headset", "ja-JP": "ヘッドセット🎧"}, "price": 8000, "stock": 0}
{"id": 105, "names": {"en-US": "Desk", "ja-JP": "デスク", "zh-CN": "桌子"}, "price": 12000, "stock": 1}
EOF

    chmod -R 777 /home/user
