#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
import csv
import os

os.makedirs('/home/user', exist_ok=True)
data = [
    ['tx_id', 'source', 'target', 'amount', 'time_seq'],
    [1, 'A', 'B', '100.0', 1],
    [2, 'A', 'C', '60.0', 2],
    [3, 'A', 'D', '10.0', 3],
    [4, 'B', 'E', '160.0', 1],
    [5, 'B', 'F', '10.0', 2],
    [6, 'C', 'X', '200.0', 1],
    [7, 'Y', 'Z', '140.0', 1],
    [8, 'Y', 'W', '10.0', 2],
    [9, 'H', 'I', '151.0', 1],
    [10, 'I', 'J', '160.0', 1],
    [11, 'J', 'K', '160.0', 1]
]

with open('/home/user/network.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerows(data)
"

    chmod -R 777 /home/user
