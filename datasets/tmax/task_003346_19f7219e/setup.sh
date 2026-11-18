#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ curl ca-certificates
    pip3 install pytest

    mkdir -p /home/user/data/subset
    mkdir -p /home/user/data/other
    mkdir -p /usr/include/nlohmann
    curl -sL https://raw.githubusercontent.com/nlohmann/json/develop/single_include/nlohmann/json.hpp -o /usr/include/nlohmann/json.hpp

    cat << 'EOF' > /home/user/data/1.json
{"dataset_id": "DS_100", "status": "ready", "data": [1,2,3]}
EOF

    cat << 'EOF' > /home/user/data/subset/2.json
{"dataset_id": "DS_101", "status": "pending"}
EOF

    cat << 'EOF' > /home/user/data/other/3.json
{"dataset_id": "DS_099", "status": "ready"}
EOF

    ln -s /home/user/data /home/user/data/subset/loop_link
    ln -s /home/user/data/1.json /home/user/data/other/link_to_1.json

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
