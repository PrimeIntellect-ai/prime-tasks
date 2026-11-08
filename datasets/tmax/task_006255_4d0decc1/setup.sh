#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++
pip3 install pytest

mkdir -p /home/user
cat << 'EOF' > /home/user/pipeline_deps.tsv
Extract_Root	Clean_Data
Extract_Root	Validate_Schema
Clean_Data	Transform_Agg
Clean_Data	Transform_Join
Validate_Schema	Transform_Join
Transform_Agg	Load_Final
Transform_Join	Load_Final
Transform_Join	Side_Effect_Task
Side_Effect_Task	Load_Final
Random_Task	Load_Final
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
