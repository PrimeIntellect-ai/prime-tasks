#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libcjson-dev libjansson-dev sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_translations.jsonl
{"id":"greeting","en":"Hello","fr":"Bonjour","ja":"\u3053\u3093\u306b\u3061\u306f"}
{"id":"farewell","en":"Goodbye","fr":"Au revoir","ja":"\u3055\u3088\u3046\u306a\u3089"}
{"id":"thanks","en":"Thank you","fr":"Merci","ja":"\u3042\u308a\u304c\u3068\u3046"}
{"id":"yes","en":"Yes","fr":"Oui","ja":"\u306f\u3044"}
EOF

    chmod -R 777 /home/user
