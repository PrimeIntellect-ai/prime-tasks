#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/factory_data
    cd /home/user/factory_data

    cat << 'EOF' > maintenance_logs.txt
2023-11-01 10:15:00 - Tech Notes: Checked Mach-101. Found issue. ErrCode:E12. Resulted in 45 minutes downtime.
2023-11-01 14:30:00 - Routine fix on Mach-204. ErrCode:E99. Replaced valve, 120 minutes downtime.
2023-11-02 09:00:00 - Mach-101 failed to start. ErrCode:E01. 30 minutes downtime.
2023-11-02 11:00:00 - Mach-300 offline. ErrCode:E44. 60 minutes downtime.
EOF

    cat << 'EOF' > sensor_telemetry.csv
timestamp,machine_id,temperature,vibration
2023-11-01 07:00:00,Mach-101,45.5,0.20
2023-11-01 08:00:00,Mach-101,46.0,0.30
2023-11-01 09:00:00,Mach-101,47.5,0.40
2023-11-01 10:00:00,Mach-101,50.0,0.80
2023-11-01 11:00:00,Mach-101,45.0,0.20
2023-11-01 12:00:00,Mach-204,60.0,1.10
2023-11-01 13:00:00,Mach-204,62.0,1.20
2023-11-01 14:00:00,Mach-204,65.0,1.50
2023-11-02 06:00:00,Mach-101,44.0,0.15
2023-11-02 07:00:00,Mach-101,44.5,0.18
2023-11-02 08:00:00,Mach-101,45.0,0.20
EOF

    chmod -R 777 /home/user
