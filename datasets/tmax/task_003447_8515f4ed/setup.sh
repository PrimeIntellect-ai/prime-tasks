#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sudo inotify-tools jq
pip3 install pytest

mkdir -p /home/user/legacy_projects/team_a /home/user/legacy_projects/team_b
mkdir -p /home/user/dropzone

cat << 'EOF' > /home/user/legacy_projects/team_a/proj1.json
{"id": 101, "project_name": "Apollo", "status": "active"}
EOF

cat << 'EOF' > /home/user/legacy_projects/team_b/proj2.csv
id,project_name,status
102,Gemini,archived
EOF

useradd -m -s /bin/bash user || true
echo "user ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/user
chmod 0440 /etc/sudoers.d/user

chmod -R 777 /home/user
