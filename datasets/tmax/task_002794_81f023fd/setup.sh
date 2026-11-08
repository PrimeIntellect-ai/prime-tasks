#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/etl_events.jsonl
{"ts": "2023-10-25 10:00:00Z", "lang": "zh", "val": 10.0, "msg": "系统 失敗"}
{"ts": "2023-10-25 19:02:00+09:00", "lang": "ja", "val": 15.0, "msg": "システム 失敗"}
{"ts": "2023-10-25 06:00:00-04:00", "lang": "zh", "val": 99.9, "msg": "系统 失敗"}
{"ts": "2023-10-25 10:05:00Z", "lang": "ja", "val": 20.0, "msg": "失敗"}
{"ts": "2023-10-25 10:10:00Z", "lang": "zh", "val": 30.0, "msg": "验证 失敗"}
{"ts": "2023-10-25 10:15:00Z", "lang": "en", "val": 100.0, "msg": "system failure"}
{"ts": "2023-10-25 10:20:00Z", "lang": "ja", "val": 40.0, "msg": "接続 失敗"}
{"ts": "2023-10-25 19:02:00+09:00", "lang": "ja", "val": 15.0, "msg": "システム 失敗"}
EOF

    chmod -R 777 /home/user
