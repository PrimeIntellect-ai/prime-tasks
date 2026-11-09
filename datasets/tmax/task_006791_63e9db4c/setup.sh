#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip time diffutils
    pip3 install pytest

    mkdir -p /home/user/pipelines
    mkdir -p /home/user/large_pipeline

    # Create small pipeline files
    cat << 'EOF' > /home/user/pipelines/core.json
{
  "jobs": {
    "build_core": {"deps": ["lint_core", "setup_env"]},
    "lint_core": {"deps": ["setup_env"]},
    "setup_env": {"deps": []}
  }
}
EOF

    cat << 'EOF' > /home/user/pipelines/plugins.json
{
  "jobs": {
    "build_plugin_a": {"deps": ["build_core"]},
    "test_plugin_a": {"deps": ["build_plugin_a"]},
    "deploy_all": {"deps": ["test_plugin_a", "build_core"]}
  }
}
EOF

    # Create the legacy old_order.txt file
    echo "setup_env build_core lint_core deploy_all build_plugin_a test_plugin_a" > /home/user/old_order.txt

    # Create a large pipeline file for benchmarking
    cat << 'EOF' > /home/user/large_pipeline/graph.json
{
  "jobs": {
    "job_0": {"deps": []},
    "job_1": {"deps": ["job_0"]},
    "job_2": {"deps": ["job_0", "job_1"]},
    "job_3": {"deps": ["job_2"]},
    "job_4": {"deps": ["job_3"]},
    "job_5": {"deps": ["job_4", "job_1"]}
  }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
