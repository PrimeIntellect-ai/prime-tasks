#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/raw_logs
    mkdir -p /home/user/processed_logs

    # Create the manifest with one entry already
    echo "log_20231001_N01.csv" > /home/user/processed_manifest.txt

    # File 1: Should be skipped because log_20231001_N01.csv is in manifest
    cat << 'EOF' | iconv -f UTF-8 -t ISO-8859-1 > "/home/user/raw_logs/System Log - 2023-10-01 - N01.csv"
# Automated System Log
# Generated at midnight
id,timestamp,status,message
1,00:01,SUCCESS,Node boot
2,00:05,FAILED,Disk space low
3,00:10,SUCCESS,Service restarted
EOF

    # File 2: Needs processing, has special characters (ñ, á) to test encoding
    cat << 'EOF' | iconv -f UTF-8 -t ISO-8859-1 > "/home/user/raw_logs/System Log - 2023-10-02 - N02.csv"
# Automated System Log
# Generated at midnight
id,timestamp,status,message
1,00:01,SUCCESS,Iniciando
2,00:05,FAILED,Conexión falló en el servidor
3,00:10,SUCCESS,Todo normal
4,00:15,ERROR,Falló la operación
EOF

    # File 3: Needs processing
    cat << 'EOF' | iconv -f UTF-8 -t ISO-8859-1 > "/home/user/raw_logs/System Log - 2023-10-03 - N03.csv"
# System Log
id,timestamp,status,message
1,00:01,FAILED,Network timeout
2,00:05,SUCCESS,Retried and ok
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
