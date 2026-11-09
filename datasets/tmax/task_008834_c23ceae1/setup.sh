#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest filelock

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/config_manager/backups
    mkdir -p /home/user/config_manager/extracted

    # Create rules.ini
    cat << 'EOF' > /home/user/config_manager/rules.ini
[Network]
legacy_ip = 192.168.1.100
new_ip = 10.200.50.5
EOF

    # Create Server A
    mkdir -p /tmp/serverA
    cat << 'EOF' > /tmp/serverA/changelog.txt
[Deployment: 2023-01-01]
CommitID: x999999
Status: APPROVED
Changes:
  - Initial setup

[Deployment: 2023-02-01]
CommitID: abc1234
Status: REJECTED
Changes:
  - Bad config

[Deployment: 2023-03-01]
CommitID: def5678
Status: APPROVED
Changes:
  - Fixed routes
EOF

    # Create a dummy large config
    echo "server_bind = 192.168.1.100:8080" > /tmp/serverA/app.conf
    for i in $(seq 1 500); do
      echo "route_$i = 192.168.1.100/24" >> /tmp/serverA/app.conf
    done

    tar -czf /home/user/config_manager/backups/serverA.tar.gz -C /tmp serverA

    # Create Server B
    mkdir -p /tmp/serverB
    cat << 'EOF' > /tmp/serverB/changelog.txt
[Deployment: 2023-01-01]
CommitID: z111111
Status: APPROVED
Changes:
  - Setup
EOF

    echo "node_ip=192.168.1.100" > /tmp/serverB/app.conf
    for i in $(seq 1 200); do
      echo "peer_$i = 192.168.1.100" >> /tmp/serverB/app.conf
    done

    tar -czf /home/user/config_manager/backups/serverB.tar.gz -C /tmp serverB

    # Create a corrupted archive
    head -c 500 /dev/urandom > /home/user/config_manager/backups/serverC_corrupted.tar.gz

    chown -R user:user /home/user/config_manager
    chmod -R 777 /home/user
