#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make wget tar
    pip3 install pytest

    # Set up the vendored cJSON library
    mkdir -p /app/vendored
    cd /app/vendored
    wget -q https://github.com/DaveGamble/cJSON/archive/refs/tags/v1.7.15.tar.gz
    tar -xzf v1.7.15.tar.gz
    rm v1.7.15.tar.gz
    cd cJSON-1.7.15

    # Introduce the intentional perturbation in the Makefile
    sed -i 's/^CC = gcc/CC = gcc_broken_typo_compiler/' Makefile || true
    sed -i '1i CC = gcc_broken_typo_compiler' Makefile

    # Set up the corpus directories and files
    mkdir -p /app/corpus/clean/subdir1
    mkdir -p /app/corpus/evil/subdir2

    # Clean corpus
    cat << 'EOF' > /app/corpus/clean/subdir1/data1.log
{
  "id": 1,
  "type": "sensor_reading",
  "data": "xyz"
}
---END_RECORD---
{
  "id": 2,
  "type": "sensor_reading",
  "calibration_error": 4.5
}
---END_RECORD---
{
  "id": 3,
  "type": "sensor_reading",
  "calibration_error": 5.0
}
---END_RECORD---
EOF

    # Evil corpus
    cat << 'EOF' > /app/corpus/evil/subdir2/data2.log
{
  "id": 4,
  "type": "sensor_reading",
  "calibration_error": 6.2
}
---END_RECORD---
{
  "id": 5,
  "type": "other_type"
}
---END_RECORD---
{
  "id": 6,
  "calibration_error": 2.0
}
---END_RECORD---
{ invalid json structure
---END_RECORD---
{
  "id": 7,
  "type": "sensor_reading",
  "calibration_error": 5.1
}
---END_RECORD---
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
