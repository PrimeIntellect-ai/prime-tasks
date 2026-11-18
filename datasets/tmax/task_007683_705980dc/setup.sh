#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the initial state using Python
    python3 -c '
import os
import tarfile
import shutil

os.makedirs("/home/user/docs/api", exist_ok=True)
os.makedirs("/home/user/docs/guides", exist_ok=True)

files_data = {
    "docs/api/endpoints.md": (
        "Title: API Endpoints\nVersion: 1.0\nStatus: Active\nAuthor: Bob\n---\n"
        "Use http://api.old.local/v1/users to get users.\n"
        "Use http://api.old.local/v1/auth to login.\n"
    ),
    "docs/api/new_endpoints.md": (
        "Title: New API Endpoints\nVersion: 2.0\nStatus: Active\nAuthor: Alice\n---\n"
        "Use https://api.new.local/v2/users to get users.\n"
        "Use http://api.old.local/v1/legacy just in case.\n"
    ),
    "docs/guides/setup.md": (
        "Title: Setup Guide\nVersion: 1.0\nStatus: Active\nAuthor: Charlie\n---\n"
        "Download from http://api.old.local/v1/downloads.\n"
    ),
    "docs/readme.md": (
        "Title: Readme\nVersion: 1.1\nStatus: Deprecated\nAuthor: Admin\n---\n"
        "Nothing to see here.\n"
    )
}

for filepath, content in files_data.items():
    full_path = os.path.join("/home/user", filepath)
    with open(full_path, "w") as f:
        f.write(content)
        f.write("Some extra filler documentation line.\n" * 100)

with tarfile.open("/home/user/docs_archive.tar.gz", "w:gz") as tar:
    tar.add("/home/user/docs", arcname="docs")

shutil.rmtree("/home/user/docs")
'

    chmod -R 777 /home/user
