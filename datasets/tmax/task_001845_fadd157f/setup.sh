#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/server_logs.jsonl
{"timestamp": 1610000000, "source": "server_alpha", "target": "server_beta", "status": "OK", "bytes": 1024}
{"timestamp": 1610000010, "source": "server_gamma", "target": "server_beta", "status": "OK", "bytes": 2048}
{"timestamp": 1610000020, "source": "server_alpha", "target": "server_beta", "status": "FAIL", "bytes": 512}
{"timestamp": 1610000030, "source": "server_delta", "target": "server_epsilon", "status": "OK", "bytes": 1024}
{"timestamp": 1610000040, "source": "server_epsilon", "target": "server_alpha", "status": "OK", "bytes": 1024}
{"timestamp": 1610000050, "source": "server_zeta", "target": "server_alpha", "status": "OK", "bytes": 1024}
{"timestamp": 1610000060, "source": "server_eta", "target": "server_alpha", "status": "OK", "bytes": 1024}
{"timestamp": 1610000070, "source": "server_theta", "target": "server_alpha", "status": "OK", "bytes": 1024}
{"timestamp": 1610000080, "source": "server_beta", "target": "server_epsilon", "status": "OK", "bytes": 1024}
{"timestamp": 1610000090, "source": "server_gamma", "target": "server_epsilon", "status": "OK", "bytes": 1024}
{"timestamp": 1610000100, "source": "server_zeta", "target": "server_delta", "status": "OK", "bytes": 1024}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
