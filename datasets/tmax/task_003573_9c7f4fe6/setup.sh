#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip jq
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/auth.log
[2023-10-01 10:00:01] INFO Connection from 192.168.1.50 - Valid token
[2023-10-01 10:05:22] WARN Connection from 10.0.0.5 - Invalid token
[2023-10-01 10:12:45] INFO Connection from 192.168.1.51 - Valid token
[2023-10-01 10:15:00] ERROR Connection from 203.0.113.42 - Executed anomalous payload via legacy_rotator.sh
[2023-10-01 10:20:11] WARN Connection from 10.0.0.8 - Malformed request
EOF

cat << 'EOF' > /home/user/legacy_rotator.sh
#!/bin/bash
# Legacy Credential Rotator v1.0
INPUT=$1
CMD=$2
# Security check
B64_KEY="czNjcjN0X2I0Y2tkMDBy"
SECRET=$(echo "$B64_KEY" | base64 -d)

if [ "$INPUT" == "$SECRET" ]; then
    eval "$CMD"
    exit 0
fi
echo "Rotating credentials..."
EOF

chmod +x /home/user/legacy_rotator.sh

cat << 'EOF' > /home/user/config.json
{
  "service": "auth_backend",
  "port": 8080,
  "password": "old_password_123"
}
EOF

chmod -R 777 /home/user
