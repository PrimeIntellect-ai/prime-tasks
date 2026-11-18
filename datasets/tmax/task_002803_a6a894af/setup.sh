#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev tar gzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/dataset_workspace
    cd /home/user/dataset_workspace

    # Create manifest
    cat << 'EOF' > manifest.csv
data_part1.csv,UTF-8
data_part2.csv,UTF-16LE
data_part3.csv,ISO-8859-1
EOF

    # Create Part 1 (UTF-8)
    cat << 'EOF' > data_part1.csv
ID,Timestamp,Sensor,Value,Notes
1,2023-01-01T10:00,TEMP_01,22.5,Normal
2,2023-01-01T10:05,TEMP_01,26.1,High
3,2023-01-01T10:10,PRESS_02,101.2,Normal
EOF

    # Create Part 2 (UTF-16LE)
    cat << 'EOF' > data_part2_utf8.csv
4,2023-01-01T10:15,TEMP_01,24.0,Normal
5,2023-01-01T10:20,TEMP_01,28.4,Critical
6,2023-01-01T10:25,TEMP_02,29.1,High
EOF
    iconv -f UTF-8 -t UTF-16LE data_part2_utf8.csv > data_part2.csv
    rm data_part2_utf8.csv

    # Create Part 3 (ISO-8859-1)
    cat << 'EOF' > data_part3_utf8.csv
7,2023-01-01T10:30,TEMP_01,25.5,High
8,2023-01-01T10:35,PRESS_01,99.8,Low
9,2023-01-01T10:40,TEMP_01,20.1,Normal
EOF
    iconv -f UTF-8 -t ISO-8859-1 data_part3_utf8.csv > data_part3.csv
    rm data_part3_utf8.csv

    # Create the archive
    tar -czf /home/user/raw_dataset.tar.gz manifest.csv data_part1.csv data_part2.csv data_part3.csv
    cd /home/user
    rm -rf /home/user/dataset_workspace

    chmod -R 777 /home/user
