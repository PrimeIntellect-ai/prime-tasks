#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/access.log
192.168.1.10 - - [10/Oct/2023:13:55:36 -0700] "GET /login?redirect_to=aHR0cHM6Ly90cnVzdGVkLmNvbS9kYXNoYm9hcmQ= HTTP/1.1" 200 1024
192.168.1.11 - - [10/Oct/2023:13:56:10 -0700] "GET /login?redirect_to=aHR0cDovL2V2aWwucGhpc2hpbmcuY29tL3N0ZWFs HTTP/1.1" 200 1024
192.168.1.12 - - [10/Oct/2023:13:58:20 -0700] "GET /login?redirect_to=aHR0cHM6Ly90cnVzdGVkLmNvbS9wcm9maWxl HTTP/1.1" 200 1024
192.168.1.13 - - [10/Oct/2023:14:00:05 -0700] "GET /login?redirect_to=aHR0cHM6Ly9hdHRhY2tlci5uZXQvZHJvcA== HTTP/1.1" 200 1024
192.168.1.14 - - [10/Oct/2023:14:05:00 -0700] "GET /login?redirect_to=aHR0cDovL3RydXN0ZWQuY29tL2h0dHBfZG93bmdyYWRl HTTP/1.1" 200 1024
EOF

    cat << 'EOF' > /home/user/authorized_keys
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM1234567890abcdefghijklmnopqrstuvwxyz alice@workstation
ssh-dss AAAAB3NzaC1kc3MAAACBAJ1234567890abcdefghijklmnopqrstuvwxyz bob@legacy-system
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC1234567890abcdefghijklmnopqrstuvwxyz charlie@dev
ssh-dss AAAAB3NzaC1kc3MAAACBAK1234567890abcdefghijklmnopqrstuvwxyz service-account-old
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
