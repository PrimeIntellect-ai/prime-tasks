#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq tar gzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/datasets
    cd /home/user/datasets

    # Exp 1: Match
    mkdir exp_001
    echo '{"status": "success", "experiment_type": "spectroscopy"}' > exp_001/meta.json
    echo "id,timestamp,intensity,wavelength\n1,1000,50,400\n2,1005,150,405\n3,1010,200,410" | sed 's/\\n/\n/g' > exp_001/readings.csv

    # Exp 2: Fail (Status mismatch)
    mkdir exp_002
    echo '{"status": "failed", "experiment_type": "spectroscopy"}' > exp_002/meta.json
    echo "id,timestamp,intensity,wavelength\n4,1015,300,415" | sed 's/\\n/\n/g' > exp_002/readings.csv

    # Exp 3: Fail (Type mismatch)
    mkdir exp_003
    echo '{"status": "success", "experiment_type": "calibration"}' > exp_003/meta.json
    echo "id,timestamp,intensity,wavelength\n5,1020,150,420" | sed 's/\\n/\n/g' > exp_003/readings.csv

    # Exp 4: Match
    mkdir exp_004
    echo '{"status": "success", "experiment_type": "spectroscopy"}' > exp_004/meta.json
    echo "id,timestamp,intensity,wavelength\n6,1025,90,425\n7,1030,110,430" | sed 's/\\n/\n/g' > exp_004/readings.csv

    tar -czf experiments.tar.gz exp_001 exp_002 exp_003 exp_004
    rm -rf exp_001 exp_002 exp_003 exp_004

    chmod -R 777 /home/user
