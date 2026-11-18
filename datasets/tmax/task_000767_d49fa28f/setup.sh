#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/config_manager/data/app1
    mkdir -p /home/user/config_manager/data/app2/logs
    mkdir -p /home/user/config_manager/data/app3

    # Create manifest
    cat << 'EOF' > /home/user/config_manager/manifest.json
{
  "targets": [
    "/home/user/config_manager/data"
  ]
}
EOF

    # Create CSV configs with secrets
    cat << 'EOF' > /home/user/config_manager/data/app1/settings.csv
id,name,value
1,db_host,localhost
2,api_key,SECRET_KEY=9876QWERTY
3,debug,true
EOF

    cat << 'EOF' > /home/user/config_manager/data/app2/users.csv
username,role,token
admin,superuser,SECRET_KEY=admin123XYZ
guest,viewer,SECRET_KEY=guest000
EOF

    # Create some JSON configs
    cat << 'EOF' > /home/user/config_manager/data/app3/config.json
{
  "version": "1.0.0",
  "enabled": true
}
EOF

    # Create symlink loops
    ln -s /home/user/config_manager/data/app1 /home/user/config_manager/data/app2/loop_to_app1
    ln -s /home/user/config_manager/data/app2 /home/user/config_manager/data/app1/loop_to_app2

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/config_manager
    chmod -R 777 /home/user
