#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user

    # Create corpus.txt
    cat << 'EOF' > /home/user/corpus.txt
Hello World! This is an MLOps task.
We are tracking experiment artifacts.
Go is an excellent language for performance.
Dimensionality reduction via random projection.
Tokenization and dataset preparation are key skills.
EOF

    # Create projection.csv (26 rows, 5 cols)
    python3 -c "
import random
random.seed(42)
with open('/home/user/projection.csv', 'w') as f:
    for _ in range(26):
        row = [str(round(random.uniform(-1, 1), 6)) for _ in range(5)]
        f.write(','.join(row) + '\n')
"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
