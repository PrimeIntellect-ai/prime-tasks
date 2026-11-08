#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk sed grep coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_config_events.txt
2024-03-01T09:00:00Z | 10.0.0.1 | admin | START | system boot
2024-03-01T10:15:22Z | 10.0.0.2 | rjones | UPDATE | param=1
2024-03-02T11:00:00Z | 10.0.0.3 | admin | RESTART | 
2024-03-05T14:32:01Z | 192.168.1.105 | jsmith | UPDATE | changed max_connections to 500
2024-03-05T14:40:00Z | 192.168.1.105 | jsmith | INVALID_LINE_MISSING_PIPES
2024-03-08T08:12:00Z | 172.16.0.4 | system | CHECK | health | extra_field
2024-03-15T00:00:00Z | 10.0.1.5 | root | DELETE | old_logs
2024-03-15T01:00:00Z | 10.0.1.5 | root | DELETE | temp_files
2024-03-15T02:00:00Z | 10.0.1.5 | root | DELETE | cache
2024-02-28T23:59:59Z | 8.8.8.8 | nobody | TEST | out of bounds date
2024-04-01T00:00:01Z | 8.8.8.8 | nobody | TEST | out of bounds date
2024-03-31T23:59:59Z | 10.0.0.99 | admin | STOP | system shutdown
EOF

    chmod -R 777 /home/user
