#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user/data/logs /home/user/reports

    cat << 'EOF' > /home/user/data/logs/srv01_metrics.csv
timestamp,server_id,cpu_temp
1600000000,SRV-01,40.0
1600000010,SRV-01,42.0
1600000020,SRV-01,
1600000030,SRV-01,46.0
1600000040,SRV-01,
1600000050,SRV-01,50.0
EOF

    cat << 'EOF' > /home/user/data/logs/srv02_metrics.json
[
  {"timestamp": 1600000005, "server_id": "SRV-02", "cpu_temp": 60.0},
  {"timestamp": 1600000015, "server_id": "SRV-02", "cpu_temp": null},
  {"timestamp": 1600000025, "server_id": "SRV-02", "cpu_temp": null},
  {"timestamp": 1600000035, "server_id": "SRV-02", "cpu_temp": 66.0}
]
EOF

    cat << 'EOF' > /home/user/data/logs/srv03_metrics.jsonl
{"timestamp": 1600000002, "server_id": "SRV-03", "cpu_temp": 30.0}
{"timestamp": 1600000012, "server_id": "SRV-03", "cpu_temp": null}
{"timestamp": 1600000022, "server_id": "SRV-03", "cpu_temp": 40.0}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
