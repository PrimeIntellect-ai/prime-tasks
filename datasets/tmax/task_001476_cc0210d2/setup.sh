#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/data_ingester/ingester
    mkdir -p /home/user/inputs

    cat << 'EOF' > /home/user/data_ingester/setup.py
from setuptools import setup, find_packages

setup(
    name='data_ingester',
    version='1.0.0',
    packages=find_packages(),
    install_requires=[
        'asyncio'
        'logging'
    ],
)
EOF

    touch /home/user/data_ingester/ingester/__init__.py

    cat << 'EOF' > /home/user/data_ingester/ingester/parser.py
def parse_record(data: bytes):
    # Fails if specific magic bytes are present in an unexpected place
    if b'\xBA\xAD\xF0\x0D' in data:
        raise ValueError("Corrupt record detected")
    return True
EOF

    cat << 'EOF' > /home/user/data_ingester/ingester/async_worker.py
import asyncio
from .parser import parse_record

async def worker(name, queue, stats):
    while True:
        data = await queue.get()
        try:
            parse_record(data)
            stats['success'] += 1
            queue.task_done()
        except Exception:
            stats['failed'] += 1
            # BUG: missing queue.task_done() here!
EOF

    cat << 'EOF' > /home/user/data_ingester/run_processor.py
import asyncio
import os
import sys
from ingester.async_worker import worker

async def main(input_dir):
    queue = asyncio.Queue()
    stats = {'success': 0, 'failed': 0}

    workers = []
    for i in range(3):
        task = asyncio.create_task(worker(f'worker-{i}', queue, stats))
        workers.append(task)

    for filename in os.listdir(input_dir):
        filepath = os.path.join(input_dir, filename)
        with open(filepath, 'rb') as f:
            for line in f:
                queue.put_nowait(line)

    await queue.join()

    for w in workers:
        w.cancel()

    with open('/home/user/success.log', 'w') as f:
        f.write(f"Success: {stats['success']}, Failed: {stats['failed']}\n")

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print("Usage: run_processor.py <input_dir>")
        sys.exit(1)
    asyncio.run(main(sys.argv[1]))
EOF

    python3 -c "
import os
for i in range(1, 6):
    with open(f'/home/user/inputs/file{i}.bin', 'wb') as f:
        if i == 3:
            f.write(b'normal_data\n\xBA\xAD\xF0\x0D_extra\n')
        else:
            f.write(b'normal_data\n')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
