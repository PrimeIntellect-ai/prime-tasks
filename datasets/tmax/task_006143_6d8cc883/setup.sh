#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/aliases
list-admin: admin@localdomain.internal
EOF

    cat << 'EOF' > /home/user/firewall.rules
-A PREROUTING -p tcp --dport 8080 -j REDIRECT --to-ports 2525
EOF

    cat << 'EOF' > /home/user/user_db.json
[
  {"username": "alice", "port": 8081},
  {"username": "bob", "port": 8082}
]
EOF

    cat << 'EOF' > /home/user/update_users.py
import json

def main():
    with open('user_db.json', 'r') as f:
        users = json.load(f)

    for u in users:
        with open('aliases', 'a') as f:
            f.write(f"list-{u['username']}: {u['username']}@localdomain.internal\n")

        with open('firewall.rules', 'a') as f:
            f.write(f"-A PREROUTING -p tcp --dport {u['port']} -j REDIRECT --to-ports 2525\n")

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
