#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc
    pip3 install pytest

    mkdir -p /home/user/experiments
    mkdir -p /home/user/bin

    # Create the experiment artifacts
    cat << 'EOF' > /home/user/experiments/runs.csv
run_id,learning_rate,accuracy
1,0.001,0.70
2,0.005,0.75
3,0.010,0.82
4,0.020,0.85
5,0.050,0.83
EOF

    # Create the mock Bayesian inference tool
    cat << 'EOF' > /home/user/bin/bayes_infer
#!/bin/bash

if [[ "$OMP_NUM_THREADS" == "1" && "$OPENBLAS_NUM_THREADS" == "1" ]]; then
    # Deterministic output
    echo '{"posterior_mean": 0.812, "posterior_variance": 0.0042, "converged": true}'
else
    # Non-deterministic output simulating numerical instability in multi-threading
    echo "{\"posterior_mean\": 0.812, \"posterior_variance\": 0.0042, \"converged\": true, \"noise\": $RANDOM}"
fi
EOF

    chmod +x /home/user/bin/bayes_infer

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
