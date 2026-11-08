#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ curl wget tar coreutils
pip3 install pytest

mkdir -p /home/user/setup_workspace
cd /home/user/setup_workspace

cat << 'EOF' > db_settings.json
{
  "metadata": {
    "env": "prod",
    "version": "v1.2.4"
  },
  "host": "db.internal",
  "port": 5432
}
EOF

cat << 'EOF' > api_limits.json
{
  "metadata": {
    "env": "staging",
    "version": "v2.0.0"
  },
  "rate_limit": 1000
}
EOF

cat << 'EOF' > feature_flags.csv
env,version,flag,enabled
dev,v3.1.0,new_ui,true
dev,v3.1.0,beta_feature,false
EOF

tar -czf /home/user/legacy_configs.tar.gz -C /home/user/setup_workspace db_settings.json api_limits.json feature_flags.csv

rm -rf /home/user/setup_workspace

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
