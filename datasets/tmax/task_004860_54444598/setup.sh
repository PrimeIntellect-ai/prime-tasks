#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os

input_file = '/home/user/input.csv'

with open(input_file, 'w', encoding='utf-8') as f:
    f.write("id,date,text\n")
    for i in range(1, 10001):
        if i % 73 == 0:
            f.write(f"{i},2023-01-01\n")
            continue
        if i % 191 == 0:
            f.write(f"{i},2023-01-01,Some text,Extra column\n")
            continue

        if i % 2 == 0:
            text = f"Review number {i}. It was an caf\\u00e9 with a \\u2603 snowman\\u0021"
        else:
            text = f"Review {i} is normal."

        if i % 5 == 0:
            text = text.replace(" ", ", ")

        if "," in text:
            f.write(f'{i},2023-05-{i%28+1:02d},"{text}"\n')
        else:
            f.write(f"{i},2023-05-{i%28+1:02d},{text}\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
