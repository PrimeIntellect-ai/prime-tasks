#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make tar gzip coreutils
    pip3 install pytest

    mkdir -p /home/user/config_data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/config_data/app1.json
{
  "app_name": "alpha_router",
  "version": "1.4.2",
  "enabled": true
}
EOF

    cat << 'EOF' > /home/user/config_data/app2.json
{
  "app_name": "beta_cache",
  "version": "2.0.0",
  "enabled": false
}
EOF

    cat << 'EOF' > /home/user/config_data/app3.json
{
  "app_name": "gamma_db",
  "version": "9.4.1",
  "enabled": true
}
EOF

    cat << 'EOF' > /home/user/config_data/app4.json
{
  "app_name": "delta_proxy",
  "version": "1.0.8",
  "enabled": true
}
EOF

    cat << 'EOF' > /home/user/config_data/history.wal
001 ADD app1.json
002 ADD app2.json
003 ADD app3.json
004 UPDATE app1.json
005 ADD app4.json
006 DELETE app2.json
007 UPDATE app3.json
008 DELETE app4.json
009 ADD app4.json
010 DELETE app4.json
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/config_data
    chown -R user:user /home/user/output
    chmod -R 777 /home/user
