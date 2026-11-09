#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg cargo rustc curl
    pip3 install pytest

    mkdir -p /app/corpora/clean /app/corpora/evil
    ffmpeg -f lavfi -i testsrc=duration=5:size=640x480:rate=30 /app/sync_feed.mp4

    python3 -c "
import os
import random

def write_csv(path, rows, alpha_func, beta_func):
    with open(path, 'w') as f:
        f.write('timestamp,sensor_alpha,sensor_beta\n')
        for i in range(rows):
            a = alpha_func(i)
            b = beta_func(a, i)
            f.write(f'{i},{a},{b}\n')

for i in range(1, 6):
    write_csv(f'/app/corpora/clean/clean_{i}.csv', 150, 
              lambda _: random.uniform(0, 10), 
              lambda a, _: a + random.uniform(0, 0.5))

write_csv('/app/corpora/evil/evil_1.csv', 149, lambda _: random.uniform(0, 10), lambda a, _: a + random.uniform(0, 0.5))
write_csv('/app/corpora/evil/evil_2.csv', 151, lambda _: random.uniform(0, 10), lambda a, _: a + random.uniform(0, 0.5))
write_csv('/app/corpora/evil/evil_3.csv', 150, lambda _: random.uniform(0, 10), lambda a, _: random.uniform(0, 10))
write_csv('/app/corpora/evil/evil_4.csv', 150, lambda _: random.uniform(0, 10), lambda a, _: -1.0 * a)
write_csv('/app/corpora/evil/evil_5.csv', 150, lambda _: float('nan'), lambda a, _: float('nan'))
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
