#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/raw_measurements.csv
timestamp,value
2023-10-01T00:10:00Z,10.0
2023-10-01T00:10:00Z,10.0
2023-10-01T00:45:00Z,12.0
2023-10-01T01:20:00Z,14.0
2023-10-01T01:20:00Z,15.0
2023-10-01T04:10:00Z,21.0
EOF

    cat << 'EOF' > /home/user/template.md
# ETL Pipeline Cleanup Report

- Original Rows Processed: {orig_rows}
- Cleaned Hourly Buckets: {clean_rows}
- Peak Average Value: {max_val}
- Lowest Average Value: {min_val}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
