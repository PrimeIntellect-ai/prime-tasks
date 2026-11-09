#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/server_metadata.json
[
  {"server_id": "srv-1", "tier": "production"},
  {"server_id": "srv-2", "tier": "production"},
  {"server_id": "srv-3", "tier": "staging"},
  {"server_id": "srv-4", "tier": "production"}
]
EOF

    cat << 'EOF' > /home/user/config_updates.csv
timestamp,server_id,config_key,config_value,update_reason
2023-10-01T09:55:00Z,srv-4,max_memory_mb,512,"Pre-existing staging value"
2023-10-01T10:00:00Z,srv-1,max_memory_mb,1024,"Initial setup"
2023-10-01T10:01:30Z,srv-2,max_memory_mb,2048,"Scale up
due to traffic spike
(approved by ops)"
2023-10-01T10:01:45Z,srv-3,max_memory_mb,8192,"Staging tests"
2023-10-01T10:03:00Z,srv-1,max_memory_mb,4096,"Emergency fix"
2023-10-01T10:06:15Z,srv-4,timeout_ms,5000,"Update timeout"
2023-10-01T10:07:00Z,srv-2,max_memory_mb,1024,"Scale down
traffic normalized"
EOF

    chmod -R 777 /home/user
