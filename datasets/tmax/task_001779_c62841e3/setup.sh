#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk jq sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_logs.txt
2023-10-01T10:00:00|192.168.1.1|/api/v1/users|200|150|{"user_id": 10}
2023-10-01T10:00:05|10.0.0.5|/api/v1/data|200|300|{"query": "test"}
2023-10-01T10:00:10|192.168.1.1|/api/v1/users|200|150|{"user_id": 10}
2023-10-01T10:00:15|192.168.1.2|/api/v1/users|200|200|{"user_id": 11}
2023-10-01T10:00:20|10.0.0.5|/api/v1/data|500|-50|{"query": "error"}
2023-10-01T10:00:25|192.168.1.3|/api/v1/users|200|250|{"user_id": 12}
2023-10-01T10:00:30|10.0.0.5|/api/v1/data|200|400|{"query": "test2"}
2023-10-01T10:00:35|192.168.1.4|/api/v1/users|200|300|{"user_id": 13}
2023-10-01T10:00:40|192.168.1.5|/api/v1/users|200|100|{"user_id": 14}
EOF

    chmod -R 777 /home/user
