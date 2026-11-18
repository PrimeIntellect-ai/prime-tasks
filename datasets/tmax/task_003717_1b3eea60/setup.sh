#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    cat << 'EOF' > /tmp/setup_data.py
import csv

data1 = [
    [1, 101, "1600000000", "The app is great, but it crashes on startup!"],
    [2, 102, "", "  "],
    [3, 103, "", "A quick brown fox jumps over the lazy dog."],
    [4, 104, "1600000300", "I love it for the features."],
    [5, 101, "1600000400", "The app is great, but it crashes on startup!"],
]

data2 = [
    [6, 105, "", "What a fantastic update... #awesome"],
    [7, 106, "1600000600", "Needs more work in the UI."],
    [8, 107, "", "Looking for a better alternative."],
    [9, 108, "", "Not bad."],
    [10, 109, "1600000900", "Terrible customer support at 5 PM."],
]

def write_csv(path, data):
    with open(path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(["ReviewID", "UserID", "Timestamp", "RawText"])
        writer.writerows(data)

write_csv('/home/user/data/feedback_part1.csv', data1)
write_csv('/home/user/data/feedback_part2.csv', data2)
EOF

    python3 /tmp/setup_data.py

    chmod -R 777 /home/user
