#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    mkdir -p /home/user/docs
    for i in $(seq -w 1 50); do
        cat <<EOF > /home/user/docs/doc_${i}.md
ID: ${i}
State: WORK_IN_PROGRESS
Location: /home/user/docs/doc_${i}.md

Documentation content for item ${i}...
EOF
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
