#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/legacy_app
    mkdir -p /home/user/firewall
    mkdir -p /home/user/audit

    cat << 'EOF' > /home/user/legacy_app/config.ini
[database]
DB_HOST=127.0.0.1
DB_PORT=5432
DB_USER=admin
DB_PASS=V2Vha09sZFBhc3N3b3Jk
EOF

    cat << 'EOF' > /home/user/legacy_app/encode_pass.sh
#!/bin/bash
if [ -z "$1" ]; then
    echo "Usage: $0 <password>"
    exit 1
fi
echo -n "$1" | base64 | rev
EOF
    chmod +x /home/user/legacy_app/encode_pass.sh

    cat << 'EOF' > /home/user/firewall/iptables.rules
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -p tcp -m tcp --dport 22 -j ACCEPT
-A INPUT -p tcp -m tcp -s 0.0.0.0/0 --dport 8080 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 443 -j ACCEPT
COMMIT
EOF

    cat << 'EOF' > /home/user/audit/sudoers_app
app_user ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart legacy_app, /bin/bash
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
