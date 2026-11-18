#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    mkdir -p /home/user/dataset
    python3 -c '
import random
import string
random.seed(42)
words = ["quantum", "neural", "tensor", "matrix", "vector", "algorithm", "dataset", "learning", "machine", "intelligence"]
for i in range(20):
    with open(f"/home/user/dataset/log_{i}.txt", "w") as f:
        for _ in range(500):
            line = []
            for _ in range(15):
                if random.random() < 0.25:
                    line.append(random.choice(words))
                else:
                    line.append("".join(random.choices(string.ascii_lowercase, k=random.randint(2, 7))))
            text = " ".join(line)
            # Inject punctuation to test the cleaning logic
            text = text.replace(" ", ", ", 3).replace(" ", ". ", 3).replace(" ", "!! ", 1)
            f.write(text + "\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
