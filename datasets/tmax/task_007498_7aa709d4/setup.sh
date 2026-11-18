#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/local_configs
    mkdir -p /home/user/remote_configs

    cat << 'EOF' > /home/user/local_configs/app1.json
{"app_name": "app1", "port": 8080, "host": "localhost"}
EOF
    cat << 'EOF' > /home/user/remote_configs/app1.json
{"app_name": "app1", "port": 8080, "host": "localhost", "ssl": true}
EOF

    cat << 'EOF' > /home/user/local_configs/app2.json
{"app_name": "app2", "db": "mysql", "retries": 5}
EOF
    cat << 'EOF' > /home/user/remote_configs/app2.json
{"app_name": "app2", "db": "postgres", "timeout": 30}
EOF

    cat << 'EOF' > /home/user/local_configs/app3.json
{"app_name": "app3", "cache": true}
EOF
    cat << 'EOF' > /home/user/remote_configs/app3.json
{app_name: "app3", "cache": true}
EOF

    cat << 'EOF' > /home/user/local_configs/app4.json
{"app_name": "app4", "workers": 4,}
EOF
    cat << 'EOF' > /home/user/remote_configs/app4.json
{"app_name": "app4", "mode": "prod"}
EOF

    cat << 'EOF' > /home/user/local_configs/app5.json
{"app_name": "app5"}
EOF
    cat << 'EOF' > /home/user/remote_configs/app5.json
{"app_name": "app5"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
