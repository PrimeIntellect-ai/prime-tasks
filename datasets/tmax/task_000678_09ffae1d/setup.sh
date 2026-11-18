#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/net_usage.csv
alice,192.168.1.10,500,1000
bob,192.168.1.11,2000,5000
charlie,192.168.1.12,100,200
dave,192.168.1.13,8000,2000
eve,192.168.1.14,4000,4000
EOF

    cat << 'EOF' > /home/user/groups.db
devs:alice,charlie
ops:bob,dave
qa:eve
EOF

    cat << 'EOF' > /home/user/quota_mgr
#!/bin/bash
read -p "Enter group to restrict: " GROUP
read -p "Enter new bandwidth limit: " LIMIT
echo "${GROUP}:${LIMIT}" > /home/user/quota_updated.log
echo "Quota updated successfully."
EOF
    chmod +x /home/user/quota_mgr

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
