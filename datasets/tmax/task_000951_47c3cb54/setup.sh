#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
import os
import datetime

base_dir = "/home/user/legacy_docs"
os.makedirs(os.path.join(base_dir, "drafts"), exist_ok=True)
os.makedirs(os.path.join(base_dir, "published", "v1"), exist_ok=True)

files = [
    {
        "path": "drafts/overview.txt",
        "mtime": "2020-05-12T10:00:00Z",
        "content_1252": b"L\x92histoire de la b\xeate",
    },
    {
        "path": "published/v1/api_specs.txt",
        "mtime": "2018-11-23T15:30:00Z",
        "content_1252": b"M\xe9thodes et propri\xe9t\xe9s",
    },
    {
        "path": "readme.txt",
        "mtime": "2023-01-02T08:15:00Z",
        "content_1252": b"Copyright \xa9 2023",
    }
]

for f in files:
    full_path = os.path.join(base_dir, f["path"])
    with open(full_path, "wb") as out:
        out.write(f["content_1252"])

    dt = datetime.datetime.strptime(f["mtime"], "%Y-%m-%dT%H:%M:%SZ")
    dt = dt.replace(tzinfo=datetime.timezone.utc)
    timestamp = dt.timestamp()
    os.utime(full_path, (timestamp, timestamp))
'

    chmod -R 777 /home/user
