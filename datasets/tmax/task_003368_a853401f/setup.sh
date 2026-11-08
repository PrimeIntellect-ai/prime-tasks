#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sudo g++ make nlohmann-json3-dev
    pip3 install pytest

    # Create user and setup sudo
    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/user
    chmod 0440 /etc/sudoers.d/user

    # Create directories
    mkdir -p /home/user/data /home/user/src /home/user/bin /home/user/output

    # Create server_meta.csv
    cat << 'EOF' > /home/user/data/server_meta.csv
ServerID,Role,Environment
srv-001,Database,Production
srv-002,Cache,Staging
srv-003,Web,Production
srv-004,Worker,Development
EOF

    # Create config_logs.txt
    cat << 'EOF' > /home/user/data/config_logs.txt
[2023-10-24T08:15:32Z] INFO: Server {srv-001} updated config [max_connections] -> 500
[2023-10-24T08:15:32Z] INFO: Server {srv-001} updated config [max_connections] -> 500
[2023-10-24T08:22:11Z] WARN: Server {srv-002} updated config [timeout] -> 30s
[2023-10-24T08:45:00Z] INFO: Server {srv-003} updated config [feature_flag_x] -> true
[2023-10-24T08:45:00Z] INFO: Server {srv-003} updated config [feature_flag_x] -> true
[2023-10-24T09:05:10Z] INFO: Server {srv-001} updated config [ssl_cert] -> rotated
[2023-10-24T09:10:00Z] INFO: Server {srv-004} updated config [log_level] -> DEBUG
[2023-10-24T09:12:00Z] INFO: Server {srv-004} updated config [log_level] -> DEBUG
[2023-10-24T09:12:00Z] INFO: Server {srv-999} updated config [unknown] -> value
EOF

    # Set permissions
    chown -R user:user /home/user
    chmod -R 777 /home/user
