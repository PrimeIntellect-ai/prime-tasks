#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server

    # Install required Python packages
    pip3 install --no-cache-dir pytest scikit-learn pandas flask fastapi uvicorn redis joblib pydantic

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create telemetry.csv
    cat << 'EOF' > /home/user/telemetry.csv
cpu_usage,memory_mb,disk_io,network_rx,latency,is_anomaly
12.5,1024,150.0,20.0,5.5,0
45.0,,1200.0,55.0,85.2,1
88.2,2048,800.0,10.0,12.0,0
99.0,4096,5000.0,,150.0,1
10.0,512,50.0,5.0,2.0,0
EOF

    # Ensure permissions
    chmod -R 777 /home/user
