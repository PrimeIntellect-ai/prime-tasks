#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/legacy.jsonl
{"user_id": 101, "bio": "I like pi\\u00f1a coladas."}
{"user_id": 102, "bio": "Just a standard bio here."}
{"user_id": 103, "bio": "Caf\\u00e9 owner in Paris."}
{"user_id": 104, "bio": "Hacker \\u0026 maker."}
{"user_id": 105, "bio": "Data engineer at \\u2601\\ufe0f Corp."}
{"user_id": 106, "bio": "El Ni\\u00f1o is a weather phenomenon."}
{"user_id": 107, "bio": "Fran\\u00e7ais"}
EOF

    cat << 'EOF' > /home/user/new.jsonl
{"user_id": 101, "bio": "I like piña coladas."}
{"user_id": 102, "bio": "Just a standard bio here."}
{"user_id": 103, "bio": "Cafe owner in Paris! Now with more text to lower ratio."}
{"user_id": 104, "bio": "Hacker & maker."}
{"user_id": 105, "bio": "Unrelated new bio completely different."}
{"user_id": 106, "bio": "El Niño is a weather phenomenon."}
{"user_id": 107, "bio": "Françoise"}
EOF

    chmod -R 777 /home/user
