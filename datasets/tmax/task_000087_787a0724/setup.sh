#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import random
random.seed(42)
with open('/home/user/dataset.csv', 'w') as f:
    for i in range(100):
        label = 1 if i % 2 == 0 else 0
        if label == 1:
            words = ["excellent", "magnificent", "fantastic", "outstanding", "brilliant"]
            text = " ".join(random.choices(words, k=3)) + " " + " ".join(["a", "is", "the", "it"] * 2)
        else:
            words = ["bad", "sad", "awful", "poor", "terrible"]
            text = " ".join(random.choices(words, k=1)) + " " + " ".join(["a", "is", "the", "it"] * 4)
        f.write(f"{label},{text}\n")
EOF
    python3 /tmp/setup.py

    chmod -R 777 /home/user
