#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/project_logs/archive/2023/
    mkdir -p /home/user/project_logs/active/

    cat << 'EOF' > /home/user/organizer_config.json
{
  "output_dir": "/home/user/organized_data",
  "component_formats": {
    "DATABASE": "csv",
    "FRONTEND": "json"
  }
}
EOF

    cat << 'EOF' > /home/user/project_logs/active/app.log
[2023-10-01 10:05:00] [INFO] [DATABASE] Connection established
[2023-10-01 10:05:05] [WARN] [FRONTEND] High latency detected
Malformed log line simulating race condition write error
[2023-10-01 10:06:00] [ERROR] [DATABASE] Timeout on query execution
EOF

    cat << 'EOF' > /home/user/project_logs/archive/2023/app.log.1
[2023-10-01 09:00:00] [INFO] [FRONTEND] Service started
[2023-10-01 09:05:00] [INFO] [DATABASE] Service started

[2023-10-01 09:10:00] [DEBUG] [UNKNOWN] This should be ignored
EOF

    cat << 'EOF' > /home/user/project_logs/archive/2023/app_error.log
[2023-10-01 09:15:00] [ERROR] [FRONTEND] Failed to render component
[2023-10-01 10:05:30] [ERROR] [DATABASE] Query syntax error "SELECT * FROM;"
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
