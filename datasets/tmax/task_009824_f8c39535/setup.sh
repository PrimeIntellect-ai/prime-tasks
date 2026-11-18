#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get clean && apt-get update
    apt-get install -y python3 python3-pip jq gawk coreutils
    pip3 install pytest

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/app.json
{"timestamp": "2023-10-01T10:05:00Z", "level": "ERROR", "message": "Connection failed [ERR-001] during sync"}
{"timestamp": "2023-10-01T10:12:00Z", "level": "INFO", "message": "Sync successful"}
{"timestamp": "2023-10-01T11:05:00Z", "level": "ERROR", "message": "Database disconnected [ERR-002]"}
{"timestamp": "2023-10-01T10:55:00Z", "level": "ERROR", "message": "Retry failed [ERR-001]"}
EOF

    cat << 'EOF' > /home/user/logs/sys.csv
2023-10-01 10:15:00,ERROR,Timeout occurred [ERR-002] on eth0
2023-10-01 10:20:00,ERROR,Disk read error [ERR-001]
2023-10-01 11:15:00,ERROR,Memory limit exceeded [ERR-002]
2023-10-01 12:00:00,WARNING,High CPU usage
EOF

    cat << 'EOF' > /home/user/template.html
<html>
<head><title>Error Report</title></head>
<body>
    <h1>Hourly Error Summary</h1>
    <table>
        <tr><th>Hour</th><th>Error Code</th><th>Count</th></tr>
        __TABLE_ROWS__
    </table>
</body>
</html>
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
