#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/project_logs

    cat << 'EOF' > /home/user/organizer_config.json
{
  "mapping": {
    "auth": "security_logs",
    "database": "backend_logs",
    "ui": "frontend_logs"
  }
}
EOF

    cat << 'EOF' > /home/user/project_logs/trace_A.log
[INFO] 2023-10-25 10:00:00 Boot sequence initiated
[DEBUG] Fetching user payload
<<<JSON_START>>>
{
  "module": "auth",
  "severity": "warning",
  "id": "x99_auth"
}
<<<JSON_END>>>
[INFO] 2023-10-25 10:00:01 Boot sequence completed
EOF

    cat << 'EOF' > /home/user/project_logs/trace_B.log
[ERROR] Connection timeout
[DEBUG] Retrying connection
<<<JSON_START>>>
{
  "module": "database",
  "severity": "critical",
  "id": "db_88_conn"
}
<<<JSON_END>>>
[FATAL] System halted
EOF

    cat << 'EOF' > /home/user/project_logs/trace_C.log
[INFO] Render complete
<<<JSON_START>>>
{
  "module": "ui",
  "severity": "info",
  "id": "ui_77_render"
}
<<<JSON_END>>>
[DEBUG] Memory cleared
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
