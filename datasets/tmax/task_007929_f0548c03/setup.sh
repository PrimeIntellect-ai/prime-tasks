#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang-go
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/artifacts

cat << 'EOF' > /home/user/artifacts/runA.json
{
  "experiment_id": "exp_alpha_01",
  "hyperparameters": {
    "learning_rate": 0.01,
    "prior_alpha": 1.5,
    "prior_beta": 2.0
  },
  "metrics": {
    "cv_score": 0.85
  }
}
EOF

cat << 'EOF' > /home/user/artifacts/runB.json
{
  "experiment_id": "exp_beta_02",
  "hyperparameters": {
    "learning_rate": 0.05,
    "prior_alpha": 0.0,
    "prior_beta": 2.0
  },
  "metrics": {
    "cv_score": 0.90
  }
}
EOF

cat << 'EOF' > /home/user/artifacts/runC.json
{
  "experiment_id": "exp_gamma_03",
  "hyperparameters": {
    "learning_rate": 0.001,
    "prior_alpha": 2.0,
    "prior_beta": 5.0
  },
  "metrics": {}
}
EOF

cat << 'EOF' > /home/user/artifacts/runD.json
{
  "experiment_id": "exp_delta_04",
  "hyperparameters": {
    "learning_rate": 0.1,
    "prior_alpha": 1.0,
    "prior_beta": 1.0
  },
  "metrics": {
    "cv_score": 0.12
  }
}
EOF

cat << 'EOF' > /home/user/artifacts/runE.json
{
  "experiment_id": "exp_epsilon_05",
  "hyperparameters": {
    "learning_rate": 0.2,
    "prior_alpha": 0.5,
    "prior_beta": 0.5
  },
  "metrics": {
    "cv_score": 0.95
  }
}
EOF

chown -R user:user /home/user/artifacts
chmod -R 777 /home/user
