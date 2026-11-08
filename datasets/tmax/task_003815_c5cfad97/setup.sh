#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user

    cat << 'EOF' > /home/user/baseline.json
["nginx", "docker", "ufw", "fail2ban", "sshd"]
EOF

    cat << 'EOF' > /home/user/incoming_configs.jsonl
{"server_id": " APP-01 ", "time": "2023-10-01T12:00:00Z", "state": ["nginx", "docker", "ufw"]}
{"server_id": "app-02", "time": 1696165200, "state": ["nginx", "docker", "sshd", "htop"]}
{"server_id": "db-01", "time": "01 Oct 2023 12:00:00 -0400", "state": ["postgres", "ufw"]}
{"server_id": "app-01", "time": "2023-10-01T12:00:00Z", "state": ["nginx", "docker", "ufw"]}
{"server_id": "app-03", "state": ["nginx"]}
{"server_id": "APP-01", "time": "2023-10-01T13:00:00Z", "state": ["nginx", "docker", "ufw", "fail2ban", "sshd"]}
{"server_id": "app-02", "time": "2023-10-01T14:00:00Z", "state": ["apache2"]}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
