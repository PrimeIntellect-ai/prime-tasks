#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scikit-learn

    useradd -m -s /bin/bash user || true

    # Generate the artifact data
    python3 -c "
import os
import json
import random

os.makedirs('/home/user/artifacts', exist_ok=True)
random.seed(42)

optimizers = ['adam', 'sgd', 'rmsprop', 'adamw']
lrs = [0.01, 0.005, 0.001, 0.0001]
batch_sizes = [16, 32, 64, 128]
dropouts = [0.1, 0.2, 0.3, 0.5]

for i in range(1, 101):
    exp_id = f'exp_{i:03d}'
    status = 'SUCCESS' if random.random() > 0.3 else 'FAILED'

    # Generate somewhat random hyperparameters
    hyperparameters = {
        'optimizer': random.choice(optimizers),
        'lr': random.choice(lrs),
        'batch_size': random.choice(batch_sizes),
    }
    if random.random() > 0.5:
        hyperparameters['dropout'] = random.choice(dropouts)

    metrics = {
        'accuracy': round(random.uniform(0.7, 0.99), 4),
        'loss': round(random.uniform(0.01, 0.5), 4)
    }

    data = {
        'experiment_id': exp_id,
        'hyperparameters': hyperparameters,
        'metrics': metrics,
        'status': status
    }

    with open(f'/home/user/artifacts/{exp_id}.json', 'w') as f:
        json.dump(data, f, indent=2)
"

    chmod -R 777 /home/user
