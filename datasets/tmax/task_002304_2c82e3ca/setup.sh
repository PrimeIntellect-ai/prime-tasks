#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Generate the UTF-16LE log file
    python3 -c "
import os
import random

log_path = '/home/user/system.log'

lines = []
for i in range(15): lines.append('INFO Error in module 1, SessionID: aaaaaaaa - timeout')
for i in range(10): lines.append('WARN Error in module 2, SessionID: bbbbbbbb - invalid arg')
for i in range(5): lines.append('CRIT Error in module 3, SessionID: cccccccc - segfault')
for i in range(2): lines.append('INFO Error in module 4, SessionID: dddddddd - db lock')
for i in range(1): lines.append('INFO Error in module 5, SessionID: eeeeeeee - retry')

for i in range(20): lines.append('DEBUG Routine check no session id here')

random.seed(42)
random.shuffle(lines)

with open(log_path, 'w', encoding='utf-16le') as f:
    for line in lines:
        f.write(line + '\n')
"

    chmod -R 777 /home/user
