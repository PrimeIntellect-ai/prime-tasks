#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        libomp-dev \
        tesseract-ocr \
        imagemagick \
        fonts-dejavu-core

    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate the rules image
    convert -size 600x200 xc:white -font DejaVu-Sans -pointsize 18 -fill black \
        -draw "text 10,30 'VALIDATION RULES:'" \
        -draw "text 10,60 'Max RetryCount = 2'" \
        -draw "text 10,90 'CPU_Usage must be between 0.0 and 100.0'" \
        -draw "text 10,120 'Memory_Usage must be between 0.0 and 100.0'" \
        /app/etl_rules.png

    # Clean corpus
    cat << 'EOF' > /app/corpus/clean/clean1.csv
EventID,Timestamp,CPU_Usage,Memory_Usage,RetryCount
1,2023-01-01T10:00:00Z,45.5,60.2,0
2,2023-01-01T10:05:00Z,99.9,10.0,1
3,2023-01-01T10:10:00Z,0.0,100.0,2
EOF

    cat << 'EOF' > /app/corpus/clean/clean2.csv
EventID,Timestamp,CPU_Usage,Memory_Usage,RetryCount
10,2023-01-01T10:00:00Z,50.0,50.0,1
11,2023-01-01T10:05:00Z,20.0,80.0,0
EOF

    # Evil corpus
    cat << 'EOF' > /app/corpus/evil/evil_retry.csv
EventID,Timestamp,CPU_Usage,Memory_Usage,RetryCount
1,2023-01-01T10:00:00Z,45.5,60.2,0
2,2023-01-01T10:05:00Z,99.9,10.0,3
EOF

    cat << 'EOF' > /app/corpus/evil/evil_cpu.csv
EventID,Timestamp,CPU_Usage,Memory_Usage,RetryCount
1,2023-01-01T10:00:00Z,105.5,60.2,0
EOF

    cat << 'EOF' > /app/corpus/evil/evil_mem.csv
EventID,Timestamp,CPU_Usage,Memory_Usage,RetryCount
1,2023-01-01T10:00:00Z,45.5,-5.0,0
EOF

    cat << 'EOF' > /app/corpus/evil/evil_dupe.csv
EventID,Timestamp,CPU_Usage,Memory_Usage,RetryCount
1,2023-01-01T10:00:00Z,45.5,60.2,0
1,2023-01-01T10:05:00Z,40.0,60.0,0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
