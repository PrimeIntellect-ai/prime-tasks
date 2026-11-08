#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/docs_incoming
    mkdir -p /home/user/docs_processed
    mkdir -p /home/user/docs_backup

    cat << 'EOF' > /home/user/docs_incoming/draft1.json
{
    "doc_id": "1001",
    "author": "lovelace",
    "content": "Introduction to analytical engines."
}
EOF

    cat << 'EOF' > /home/user/docs_incoming/draft2.xml
<doc>
    <doc_id>1002</doc_id>
    <author>turing</author>
    <content>On computable numbers.</content>
</doc>
EOF

    cat << 'EOF' > /home/user/docs_incoming/draft3.json
{
    "doc_id": "1003",
    "author": "hopper",
    "content": "Compilers and debugging."
}
EOF

    chmod -R 777 /home/user
