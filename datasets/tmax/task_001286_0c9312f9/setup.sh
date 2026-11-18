#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git golang
    pip3 install pytest

    mkdir -p /app/vendor/gocsv
    git clone https://github.com/gocarina/gocsv.git /app/vendor/gocsv
    echo 'func init() { panic("UNAUTHORIZED MODIFICATION") }' >> /app/vendor/gocsv/csv.go

    mkdir -p /home/user/data/clean_corpus /home/user/data/evil_corpus /home/user/pipeline

    cat << 'EOF' > /home/user/data/clean_corpus/1.csv
timestamp,sensor_id,value,notes
2023-01-01T00:00:00Z,sensor1,10.5,normal operation
2023-01-01T00:01:00Z,sensor1,11.0,normal operation
EOF

    cat << 'EOF' > /home/user/data/evil_corpus/1.csv
timestamp,sensor_id,value,notes
2023-01-01T00:00:00Z,sensor1,10.5,=cmd|' /C calc'!A0
EOF

    python3 -c "print('timestamp,sensor_id,value,notes\n2023-01-01T00:00:00Z,sensor1,10.5,' + 'A'*501)" > /home/user/data/evil_corpus/2.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
