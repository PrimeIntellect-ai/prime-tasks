#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest aiohttp

    # Create raw data directory and files
    mkdir -p /home/user/raw_data

    cat << 'EOF' > /home/user/raw_data/nodes.csv
node_id,researcher_name
1,Alice
2,Bob
3,Charlie
4,Diana
EOF

    cat << 'EOF' > /home/user/raw_data/edges.csv
source_id,target_id,raw_collaborations
1,2,10
1,3,5
2,4,20
3,4,10
EOF

    # Create vendored package
    mkdir -p /app/graph_transaction_lib/graph_transaction_lib

    cat << 'EOF' > /app/graph_transaction_lib/graph_transaction_lib/locks.py
import asyncio

class NodeLocker:
    def __init__(self):
        self.locks = {}

    def get_lock(self, node_id):
        if node_id not in self.locks:
            self.locks[node_id] = asyncio.Lock()
        return self.locks[node_id]

    async def acquire_edge_locks(self, src, dst):
        # DELIBERATE PERTURBATION: Locking in parameter order causes deadlocks
        # if called concurrently with (A, B) and (B, A).
        lock1 = self.get_lock(src)
        lock2 = self.get_lock(dst)
        await lock1.acquire()
        # small sleep to guarantee the race condition occurs during tests
        await asyncio.sleep(0.1) 
        await lock2.acquire()
        return (lock1, lock2)
EOF

    cat << 'EOF' > /app/graph_transaction_lib/graph_transaction_lib/graph.py
from .locks import NodeLocker

class ThreadSafeGraph:
    def __init__(self):
        self.locker = NodeLocker()
        self.edges = {}

    async def update_edge(self, src, dst, weight):
        lock1, lock2 = await self.locker.acquire_edge_locks(src, dst)
        try:
            self.edges[(src, dst)] = weight
        finally:
            lock2.release()
            lock1.release()
EOF

    cat << 'EOF' > /app/graph_transaction_lib/graph_transaction_lib/__init__.py
from .graph import ThreadSafeGraph
from .locks import NodeLocker
EOF

    cat << 'EOF' > /app/graph_transaction_lib/setup.py
from setuptools import setup, find_packages

setup(
    name="graph_transaction_lib",
    version="1.0.0",
    packages=find_packages(),
)
EOF

    pip3 install -e /app/graph_transaction_lib

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
