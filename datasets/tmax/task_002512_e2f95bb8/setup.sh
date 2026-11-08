#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
import os
log_content = """[2023-10-27T10:00:00Z] INFO JOB_123 - Processed record café
[2023-10-27T10:01:00Z] ERROR JOB_124 - データエラー 
MALFORMED LINE INVALID
[2023-10-27T10:03:00Z] INFO JOB_123 - Processed record cafe\u0301
[2023-10-27T10:04:59Z] INFO JOB_123 - PROCESSED RECORD CAFÉ 
[2023-10-27T10:06:00Z] INFO JOB_123 - Processed record cafe\u0301
[2023-10-27T10:07:00Z] INFO JOB_999 - Normal operation
[2023-10-27T10:09:00Z] INFO JOB_123 - processed record café
[2023-10-27T10:11:00Z] WARN JOB_124 - データエラー
"""
with open("/home/user/etl_logs.txt", "w", encoding="utf-8") as f:
    f.write(log_content)
'

    chmod -R 777 /home/user
