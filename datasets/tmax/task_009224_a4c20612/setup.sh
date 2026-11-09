#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
import os

os.makedirs("/home/user/logs", exist_ok=True)

logs = {
    "node1.log": [
        "[2023-10-24 14:05:00] INFO Startup complete\n",
        "[2023-10-24 14:15:22] ERROR Database connection failed\n",
        "[2023-10-24 14:45:10] ERROR Timeout on endpoint /api/v1/users\n",
        "[2023-10-24 15:02:00] ERROR Database connection failed\n"
    ],
    "node2.log": [
        "[2023-10-24 14:10:00] WARN High memory usage\n",
        "[2023-10-24 14:16:01] ERROR Database connection failed\n",
        "[2023-10-24 15:15:00] ERROR Null pointer exception in AuthManager\n",
        "[2023-10-24 15:16:00] ERROR Null pointer exception in AuthManager\n"
    ],
    "node3.log": [
        "[2023-10-24 14:20:00] ERROR Disk space critically low\n",
        "[2023-10-24 15:30:00] ERROR Disk space critically low\n",
        "[2023-10-24 15:35:00] INFO Cleanup job finished\n"
    ]
}

for filename, lines in logs.items():
    with open(f"/home/user/logs/{filename}", "w") as f:
        f.writelines(lines)
'

    chmod -R 777 /home/user
