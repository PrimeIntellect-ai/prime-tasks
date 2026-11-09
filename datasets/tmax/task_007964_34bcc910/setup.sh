#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/test_team_a.txt
ALLOW /api/login
ALLOW /public/assets
ALLOW /admin/dashboard
ALLOW /api/users
EOF

cat << 'EOF' > /home/user/test_team_b.txt
ALLOW /api/users
ALLOW /public/images
ALLOW /internal/metrics
ALLOW /internal/health
ALLOW /blog/posts
EOF

cat << 'EOF' > /home/user/test_constraints.txt
DENY /admin
DENY /internal
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
