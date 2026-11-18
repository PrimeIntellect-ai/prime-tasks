#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_data.py
import random
random.seed(42)

with open('/home/user/events.csv', 'w') as f:
    f.write('id,category,value,label\n')
    for i in range(1, 1001):
        cat = random.choice(['A', 'B', 'C'])
        val = random.randint(10, 100)
        # Add some signal so Naive Bayes isn't completely random
        if cat == 'A':
            label = 1 if random.random() > 0.3 else 0
        elif cat == 'B':
            label = 1 if random.random() > 0.7 else 0
        else:
            label = 1 if random.random() > 0.5 else 0
        f.write(f"{i},{cat},{val},{label}\n")

with open('/home/user/bootstrap_indices.txt', 'w') as f:
    for _ in range(100):
        indices = [str(random.randint(1, 1000)) for _ in range(1000)]
        f.write(",".join(indices) + "\n")
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    chmod -R 777 /home/user
