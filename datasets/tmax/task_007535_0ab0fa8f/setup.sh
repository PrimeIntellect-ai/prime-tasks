#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/packages.db
web_server: http config logger
http: tcp network
tcp: network logger
network: system
logger: filesystem
config: filesystem system
filesystem: disk
disk: system
# Cycle:
auth: crypto session
session: cache config
cache: memory
memory: system auth
EOF

    cat << 'EOF' > /home/user/app/handler.sh
#!/bin/bash
read -r line
# Buggy param parsing
pkg=$(echo "$line" | grep -o 'pkg=[^&]*' | cut -d= -f2)

# Buggy recursive resolution (infinite loop on cycles)
resolve() {
    local target=$1
    local deps=$(grep "^$target:" /home/user/app/packages.db | cut -d: -f2)
    for d in $deps; do
        echo "$d"
        resolve "$d"
    done
}

result=$(resolve "$pkg" | sort | uniq)
echo "SUCCESS: $result"
EOF

    chmod +x /home/user/app/handler.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
