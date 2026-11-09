#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip rustc cargo
pip3 install pytest

mkdir -p /home/user

# Create the auth log
cat << 'EOF' > /home/user/auth.log
[2023-10-25T08:10:12Z] | FAILED | user: test | payload: dGVzdHVzZXI=
[2023-10-25T08:15:30Z] | FAILED | user: admin | payload: YWRtaW4nIE9SIDE9MSAtLQ==
[2023-10-25T08:16:45Z] | FAILED | user: root | payload: dW5pb24gc2VsZWN0IDEsdXNlcm5hbWUsMzIz
[2023-10-25T08:20:01Z] | FAILED | user: guest | payload: PGh0bWw+aGVsbG88L2h0bWw+
[2023-10-25T08:25:12Z] | FAILED | user: unknown | payload: PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==
EOF

# Create the dummy auth_service
cat << 'EOF' > /home/user/auth_service
#!/bin/bash
PAYLOAD="$1"

# Simulate vulnerability
if [[ "$PAYLOAD" == *"OR 1=1"* ]]; then
    exit 0 # bypass
elif [[ "$PAYLOAD" == *"union select"* ]]; then
    exit 139 # segfault
else
    exit 1 # safe reject
fi
EOF
chmod +x /home/user/auth_service

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
