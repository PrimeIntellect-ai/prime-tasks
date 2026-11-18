#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/latency_profiles.json
{
  "workload_sizes": [10.0, 20.0, 30.0, 40.0, 50.0],
  "bin_centers": [1.0, 2.0, 3.0, 4.0, 5.0],
  "version_a_histograms": [
    [0.2, 0.2, 0.2, 0.2, 0.2],
    [0.1, 0.2, 0.4, 0.2, 0.1],
    [0.05, 0.1, 0.2, 0.4, 0.25],
    [0.1, 0.1, 0.2, 0.3, 0.3],
    [0.2, 0.3, 0.3, 0.1, 0.1]
  ],
  "version_b_histograms": [
    [0.1, 0.2, 0.4, 0.2, 0.1],
    [0.05, 0.1, 0.2, 0.4, 0.25],
    [0.01, 0.04, 0.15, 0.4, 0.4],
    [0.0, 0.05, 0.1, 0.25, 0.6],
    [0.0, 0.0, 0.05, 0.15, 0.8]
  ]
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
