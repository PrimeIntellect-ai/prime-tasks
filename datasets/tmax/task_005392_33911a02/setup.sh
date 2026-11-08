#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq bc
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/sim_project

    cat << 'EOF' > /home/user/sim_project/experiment_workflow.ipynb
{
 "cells": [
  {
   "cell_type": "code",
   "execution_count": 1,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Define parameters\n",
    "STEP_SIZES = [0.01, 0.05, 0.10, 0.45, 0.60, 0.85, 0.15, 0.20, 1.10, 0.25]"
   ]
  }
 ],
 "metadata": {},
 "nbformat": 4,
 "nbformat_minor": 5
}
EOF

    cat << 'EOF' > /home/user/sim_project/integrator.sh
#!/bin/bash
STEP=$1

# Simulate divergence for step sizes >= 0.5
is_divergent=$(echo "$STEP >= 0.5" | bc)

if [ "$is_divergent" -eq 1 ]; then
    # Divergence simulation: sleep for 300ms, exit 1
    sleep 0.3
    echo "DIVERGENCE"
    exit 1
else
    # Stable simulation: sleep for a deterministic time based on step size to mock computation
    # Time = 50ms + (step * 100)ms
    sleep_time=$(echo "0.05 + $STEP * 0.1" | bc)
    sleep $sleep_time
    echo "SUCCESS"
    exit 0
fi
EOF

    chmod +x /home/user/sim_project/integrator.sh
    chmod -R 777 /home/user
