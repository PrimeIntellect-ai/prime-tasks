#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    mkdir -p /home/user
    cat << 'EOF' > /home/user/setup_data.py
import pandas as pd
import numpy as np

data = {
    'id': [1, 2, 3, 1, 2, 4],
    'timestamp': ['2023-01-01 10:00', '2023-01-01 10:05', '2023-01-01 10:10',
                  '2023-01-01 10:15', '2023-01-01 10:20', '2023-01-01 10:25'],
    'user_name': ["RenÃ©", "JosÃ©", "Alice", "RenÃ©", "JosÃ©", "Bob"],
    'email': ['rene@example.com', 'jose@test.org', 'alice@domain.com',
              'rene@example.com', 'jose@test.org', 'bob@test.org'],
    'score': [85.0, np.nan, 95.0, 85.0, np.nan, 100.0],
    'retry_run_id': ['run1', 'run1', 'run1', 'run2', 'run2', 'run2']
}
df = pd.DataFrame(data)
df.to_csv('/home/user/raw_data.csv', index=False)
EOF
    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
