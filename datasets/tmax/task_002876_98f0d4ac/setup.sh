#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq iptables
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/traffic.json
[
    {"source_ip": "192.168.1.50", "headers": {"Host": "staging.local", "Cookie": "session=123", "Authorization": "Basic dXNlcjpwYXNz"}},
    {"source_ip": "10.0.0.5", "headers": {"Host": "staging.local", "Cookie": "admin_session=abcxyz; locale=en", "Authorization": "Bearer secret_token_1"}},
    {"source_ip": "10.0.0.5", "headers": {"Host": "staging.local", "Cookie": "admin_session=def456", "Authorization": "Bearer secret_token_2"}},
    {"source_ip": "10.0.0.5", "headers": {"Host": "staging.local", "Cookie": "admin_session=ghi789", "User-Agent": "curl/7.68.0"}},
    {"source_ip": "172.16.0.2", "headers": {"Host": "staging.local", "Cookie": "admin_session=jkl012", "Authorization": "Basic YWRtaW46c3VwZXJzZWNyZXQ="}},
    {"source_ip": "192.168.1.100", "headers": {"Host": "staging.local", "User-Agent": "Mozilla/5.0"}}
]
EOF

    cat << 'EOF' > /home/user/sshd_config
# Port 22
#ListenAddress 0.0.0.0

# Authentication:
#PermitRootLogin yes
#StrictModes yes
#MaxAuthTries 6
#MaxSessions 10

# To disable tunneled clear text passwords, change to no here!
PasswordAuthentication yes
#PermitEmptyPasswords no
EOF

    chmod -R 777 /home/user
