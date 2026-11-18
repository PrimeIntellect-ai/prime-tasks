#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk sed grep coreutils
    pip3 install pytest

    # Create directories
    mkdir -p /app/bin
    mkdir -p /home/user/mnt/data

    # Create dummy audio file
    touch /app/emergency_alert.wav

    # Create mock whisper-cli
    cat << 'EOF' > /usr/local/bin/whisper-cli
#!/bin/bash
echo "The network connectivity has failed with storage error code ENOSPC"
EOF
    chmod +x /usr/local/bin/whisper-cli

    # Create mock oracle_parse_metrics
    cat << 'EOF' > /app/bin/oracle_parse_metrics
#!/bin/bash
awk '/CRITICAL/ {print $3 "-ENOSPC"}'
EOF
    chmod +x /app/bin/oracle_parse_metrics

    # Create sample logs
    cat << 'EOF' > /app/sample_logs.txt
2023-10-01 12:00:00 1234 INFO System started
2023-10-01 12:01:00 5678 CRITICAL Disk full
2023-10-01 12:02:00 9012 WARN High memory
2023-10-01 12:03:00 3456 CRITICAL Network down
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
