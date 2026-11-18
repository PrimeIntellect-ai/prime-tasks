#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/artifacts

    cat << 'EOF' > /home/user/artifacts/run_1.json
{
  "run_id": "RUN-001",
  "description": "Baseline model training with standard features.",
  "schema": {
    "user_id": "string",
    "click_count": "int64",
    "probability": "float64"
  }
}
EOF

    cat << 'EOF' > /home/user/artifacts/run_2.json
{
  "run_id": "RUN-002",
  "description": "Pipeline execution completed but memory usage was slightly higher than expected.",
  "schema": {
    "user_id": "string",
    "click_count": "float64",
    "probability": "float64"
  }
}
EOF

    cat << 'EOF' > /home/user/artifacts/run_3.json
{
  "run_id": "RUN-003",
  "description": "Hyperparameter tuning job over the weekend.",
  "schema": {
    "user_id": "string",
    "click_count": "int64",
    "probability": "float64"
  }
}
EOF

    cat << 'EOF' > /home/user/artifacts/run_4.json
{
  "run_id": "RUN-004",
  "description": "Encountered missing values in the raw logs causing unexpected type casting in the feature engineering step.",
  "schema": {
    "user_id": "string",
    "click_count": "float64",
    "probability": "float64"
  }
}
EOF

    cat << 'EOF' > /home/user/artifacts/run_5.json
{
  "run_id": "RUN-005",
  "description": "Job failed midway due to OOM kill on the worker nodes.",
  "schema": {
    "user_id": "string",
    "click_count": "float64",
    "probability": "float64"
  }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
