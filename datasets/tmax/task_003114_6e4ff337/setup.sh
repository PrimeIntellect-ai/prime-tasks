#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make wget ca-certificates
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    wget -qO /home/user/json.hpp https://raw.githubusercontent.com/nlohmann/json/v3.11.2/single_include/nlohmann/json.hpp

    cat << 'EOF' > /home/user/requests.json
[
  {"req_id": "r01", "user_id": "u1", "timestamp": 1000, "payload": "SGVsbG8="},
  {"req_id": "r02", "user_id": "u1", "timestamp": 1005, "payload": "V29ybGQ="},
  {"req_id": "r03", "user_id": "u1", "timestamp": 1008, "payload": "RXhjZWVkZWQ="},
  {"req_id": "r04", "user_id": "u2", "timestamp": 1009, "payload": "VGVzdA=="},
  {"req_id": "r05", "user_id": "u1", "timestamp": 1011, "payload": "QWdhaW4="},
  {"req_id": "r06", "user_id": "u2", "timestamp": 1010, "payload": "UGF5bG9hZA=="},
  {"req_id": "r07", "user_id": "u2", "timestamp": 1018, "payload": "VGhyZWU="},
  {"req_id": "r08", "user_id": "u2", "timestamp": 1019, "payload": "Rm91cg=="}
]
EOF

    chmod -R 777 /home/user
