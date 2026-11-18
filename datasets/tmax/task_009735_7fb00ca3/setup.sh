#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl wget gawk sed
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/remote_data
    cd /home/user/remote_data

    cat << 'EOF' > sensor_log.csv
2023-10-01T10:00:00Z,S1,10.0
2023-10-01T10:01:00Z,S1,12.0
2023-10-01T10:02:00Z,S2,5.0
2023-10-01T10:03:00Z,S1,14.0
2023-10-01T10:04:00Z,S1,10.0
2023-10-01T10:05:00Z,S2,7.0
2023-10-01T10:06:00Z,S2,9.0
2023-10-01T10:07:00Z,S3,15.5
2023-10-01T10:08:00Z,S3,16.5
EOF

    # Generate report_template.md without using forbidden Apptainer build variables
    python3 -c '
a = "{{"
b = "}}"
template = f"""# Sensor Report

## Sensor S1
Latest 3-point Rolling Avg: {a}S1_AVG{b}

## Sensor S2
Latest 3-point Rolling Avg: {a}S2_AVG{b}

## Sensor S3
Latest 3-point Rolling Avg: {a}S3_AVG{b}
"""
with open("report_template.md", "w") as f:
    f.write(template)
'

    # Create an environment script to ensure the server starts when the container is executed
    cat << 'EOF' > /.singularity.d/env/99-server.sh
if [ ! -f /tmp/server.pid ]; then
    (cd /home/user/remote_data && python3 -m http.server 8080 >/dev/null 2>&1 & echo $! > /tmp/server.pid)
    sleep 1
fi
EOF
    chmod +x /.singularity.d/env/99-server.sh

    chown -R user:user /home/user
    chmod -R 777 /home/user
