#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go zip gzip tar
    pip3 install pytest

    mkdir -p /home/user/setup_workspace
    cd /home/user/setup_workspace

    # Create JSON records
    cat << 'EOF' > valid1.json
{"id": "A1", "status": "valid", "value": 10.5}
{"id": "A2", "status": "error", "value": 0.0}
{"id": "A3", "status": "valid", "value": 42.1}
EOF

    cat << 'EOF' > valid2.json
{"id": "B1", "status": "pending", "value": 1.1}
{"id": "B2", "status": "valid", "value": 99.9}
EOF

    cat << 'EOF' > valid3.json
{"id": "C1", "status": "valid", "value": 3.14}
{"id": "C2", "status": "valid", "value": 2.71}
{"id": "C3", "status": "corrupt", "value": -1}
EOF

    # Compress to txt.gz
    gzip -c valid1.json > sensorA.txt.gz
    gzip -c valid2.json > sensorB.txt.gz
    gzip -c valid3.json > sensorC.txt.gz

    # Create zip archives
    zip experiment_1.zip sensorA.txt.gz sensorB.txt.gz
    zip experiment_2.zip sensorC.txt.gz

    # Create tar payload directory
    mkdir -p dataset_payload
    mv experiment_1.zip experiment_2.zip dataset_payload/
    cd dataset_payload
    ln -s . loop_dir
    cd ..

    # Create the final tar.gz archive
    tar -czf /home/user/dataset.tar.gz -C dataset_payload .

    # Clean up setup workspace
    cd /home/user
    rm -rf /home/user/setup_workspace

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
