#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/artifacts

    cat << 'EOF' > /home/user/artifacts/run_A.json
{
    "experiment_id": "exp_A",
    "latencies": [10.2, 11.5, 9.8, 10.5, 12.1, 10.9, 9.5, 11.1, 10.4, 10.8],
    "successes": 88,
    "total_trials": 100
}
EOF

    cat << 'EOF' > /home/user/artifacts/run_B.json
{
    "experiment_id": "exp_B",
    "latencies": [45.2, 48.1, 42.5, 46.0, 44.8, 47.3, 49.1, 41.2, 45.5, 46.8],
    "successes": 45,
    "total_trials": 50
}
EOF

    cat << 'EOF' > /home/user/artifacts/run_C.json
{
    "experiment_id": "exp_C",
    "latencies": [5.1, 5.8, 4.9, 6.2, 5.5, 5.0, 5.7, 4.8, 6.1, 5.3],
    "successes": 15,
    "total_trials": 20
}
EOF

    chmod -R 777 /home/user
