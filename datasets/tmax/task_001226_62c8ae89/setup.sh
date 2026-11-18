#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget unzip build-essential
    pip3 install pytest

    # 1. Create the vendored package with perturbations
    mkdir -p /app
    cd /app
    wget -qO libb64.zip "https://sourceforge.net/projects/libb64/files/libb64/libb64/libb64-1.2.src.zip/download"
    unzip libb64.zip
    rm libb64.zip

    # Perturb Makefile
    # If CC is defined, replace it, otherwise add it at the top
    if grep -q "^CC" /app/libb64-1.2/Makefile; then
        sed -i 's/^CC.*/CC = gcc-9/' /app/libb64-1.2/Makefile
    else
        sed -i '1i CC = gcc-9' /app/libb64-1.2/Makefile
    fi

    # Perturb source
    sed -i '/#include <string.h>/d' /app/libb64-1.2/src/cdecode.c

    # 2. Create the crash log
    mkdir -p /var/log
    cat << 'EOF' > /var/log/telemetry_crash.log
[ERROR] 2023-10-27T10:00:00Z Container telemetry-processor crashed.
[FATAL] Unhandled exception in legacy_parser.sh
[TRACE] Processing payload file: cache_tmp_9912.b64
[DEBUG] Decoded output preview: {"sensor_id": 12, "data": "$(rm -rf /)"}
[ERROR] sh: 1: rm: Permission denied
[FATAL] Downstream script terminated unexpectedly on input containing shell metacharacters: $ ( ) ; | &
EOF

    # 3. Create the clean and evil corpus
    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate Clean Corpus
    for i in $(seq 1 10); do
        echo "SGVsbG8gV29ybGQK" > /app/corpus/clean/file_$i.b64
        echo "VmFsaWQgRGF0YQ==" >> /app/corpus/clean/file_$i.b64
    done

    # Generate Evil Corpus
    for i in $(seq 1 10); do
        echo "SGVsbG8gV29ybGQK" > /app/corpus/evil/evil_$i.b64
        echo 'VmFs$aWQgR;GF0YQ==' >> /app/corpus/evil/evil_$i.b64
    done

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
