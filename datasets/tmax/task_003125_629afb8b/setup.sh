#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest rdflib networkx

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.json
[
    {"_id": "1", "meta": {"author": {"handle": "alice"}}, "content": {"mentions": [{"u": "bob"}, {"u": "charlie"}]}},
    {"_id": "2", "meta": {"author": {"handle": "bob"}}, "content": {"mentions": [{"u": "charlie"}]}},
    {"_id": "3", "meta": {"author": {"handle": "charlie"}}, "content": {"mentions": [{"u": "alice"}]}},
    {"_id": "4", "meta": {"author": {"handle": "david"}}, "content": {"mentions": [{"u": "charlie"}]}},
    {"_id": "5", "meta": {"author": {"handle": "eve"}}, "content": {"mentions": [{"u": "david"}, {"u": "alice"}]}}
]
EOF

    chmod -R 777 /home/user
