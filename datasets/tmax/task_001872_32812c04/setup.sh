#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils grep
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create a fixed random seed for shuf
    echo "my_fixed_random_seed_for_shuf_12345" > /home/user/random_seed

    # Generate artifacts.csv
    cat << 'EOF' > /home/user/artifacts.csv
run_id,accuracy,loss,latency_ms
run_001,0.92,0.11,45.2
run_002,0.88,0.15,N/A
run_003,0.95,0.08,50.1
run_004,0.70,0.45,30.0
run_invalid_1,0.99,0.01
run_005,0.91,0.12,44.4
run_006,0.89,0.16,42.1
run_007,0.94,0.09,48.9
run_008,0.85,0.20,35.5
run_009,0.96,0.07,52.3
run_010,0.93,0.10,47.0
run_011,0.87,0.18,39.8
run_012,0.82,0.25,32.1
run_013,0.98,0.05,55.0
run_014,0.90,0.13,43.2
run_015,0.86,0.19,38.5
run_016,0.97,0.06,53.4
run_017,0.84,0.22,34.2
run_invalid_2,0.90,error,40.0
run_018,0.91,0.11,45.0
run_019,0.88,0.15,41.1
run_020,0.95,0.08,49.5
run_021,0.75,0.35,31.5
run_022,0.92,0.12,46.2
run_023,0.89,0.16,42.8
run_024,0.94,0.09,48.1
run_025,0.85,0.20,36.0
run_026,0.96,0.07,51.5
run_027,0.93,0.10,47.8
run_028,0.87,0.18,40.5
run_029,0.83,0.24,33.0
run_030,0.98,0.05,54.2
run_031,0.90,0.14,43.8
run_032,0.86,0.19,39.0
run_033,0.97,0.06,52.8
run_034,0.84,0.22,34.8
run_035,0.91,0.12,45.5
run_036,0.88,0.16,41.8
run_037,0.95,0.08,49.9
run_038,0.78,0.30,32.5
run_039,0.92,0.11,46.8
run_040,0.89,0.15,42.5
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
