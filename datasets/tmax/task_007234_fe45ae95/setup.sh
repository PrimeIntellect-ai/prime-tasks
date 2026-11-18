#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip locales tzdata
    pip3 install pytest

    # Generate the required locale for the task
    locale-gen de_DE.UTF-8

    # Create necessary directories
    mkdir -p /home/user/logs /home/user/config

    # Create the network log file
    cat << 'EOF' > /home/user/logs/network_trace.log
[INFO] System boot sequence initiated.
[DEBUG] Loading kernel modules...
[CRITICAL] AUTH_BINDING_ESTABLISHED at 192.168.100.45:8081 successfully.
[WARN] Deprecated API call in module fs_ext4.
[INFO] Starting mock services.
EOF

    # Create the services configuration file
    cat << 'EOF' > /home/user/config/services.json
{
  "services": {
    "auth-service": {
      "command": "/bin/auth_mock",
      "depends_on": []
    },
    "db-service": {
      "command": "/bin/db_mock",
      "depends_on": []
    },
    "api-gateway": {
      "command": "/usr/bin/python3 /home/user/api_gateway.py",
      "depends_on": []
    }
  }
}
EOF

    # Create the user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
