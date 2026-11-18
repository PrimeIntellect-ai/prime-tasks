#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc datamash
    pip3 install pytest

    mkdir -p /app

    # Create dummy audio file
    touch /app/backup_log.wav

    # Create transcriber mock
    cat << 'EOF' > /usr/local/bin/transcriber
#!/bin/bash
if [ "$1" == "/app/backup_log.wav" ]; then
    echo "At timestamp 1004, the value is 55. At timestamp 1009, the value is 61. At timestamp 1015, the value is 48."
else
    echo "Error: Invalid file."
fi
EOF
    chmod +x /usr/local/bin/transcriber

    # Create raw_data.csv
    cat << 'EOF' > /app/raw_data.csv
Timestamp,SensorA,SensorB
1001,50,110
1002,52,114
1003,49,108
1004,NaN,120
1005,53,116
1006,56,122
1007,58,126
1008,54,118
1009,NaN,132
1010,60,130
1011,59,128
1012,62,134
1013,63,136
1014,57,124
1015,NaN,106
EOF

    # Create eval_data.csv
    cat << 'EOF' > /app/eval_data.csv
Timestamp,SensorA
2001,65
2002,68
2003,70
EOF

    # Create hidden evaluation truth
    cat << 'EOF' > /app/.hidden_truth.csv
Timestamp,SensorB
2001,140
2002,146
2003,150
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
