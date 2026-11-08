#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/workspace

    cat << 'EOF' > /tmp/setup.py
import os
import json
import zipfile

workspace = "/home/user/workspace"
artifacts_dir = os.path.join(workspace, "artifacts")
os.makedirs(artifacts_dir, exist_ok=True)

# 1. Create JSON Index
repo_index = {
    "ART-001": {"filename": "alpha-1.0.0.zip", "project": "Alpha", "version": "1.0.0"},
    "ART-002": {"filename": "alpha-2.0.0.zip", "project": "Alpha", "version": "2.0.0"},
    "ART-003": {"filename": "beta-1.0.0.zip", "project": "Beta", "version": "1.0.0"},
    "ART-004": {"filename": "beta-1.1.0.zip", "project": "Beta", "version": "1.1.0"},
    "ART-005": {"filename": "gamma-1.0.0.zip", "project": "Gamma", "version": "1.0.0"}
}
with open(os.path.join(workspace, "repo_index.json"), "w") as f:
    json.dump(repo_index, f, indent=4)

# 2. Create Multi-line Log
log_content = """[START]
Date: 2023-10-25
Artifact-ID: ART-001
Status: SUCCESS
Message: Good.
[END]
[START]
Date: 2023-10-26
Artifact-ID: ART-002
Status: WARNING
Message: Minor metadata issue.
[END]
[START]
Date: 2023-10-27
Artifact-ID: ART-003
Status: SUCCESS
Message: Perfect.
[END]
[START]
Date: 2023-10-28
Artifact-ID: ART-004
Status: SUCCESS
Message: Corrupted file uploaded.
[END]
[START]
Date: 2023-10-29
Artifact-ID: ART-005
Status: FAILED
Message: Bad upload.
[END]
"""
with open(os.path.join(workspace, "ingest.log"), "w") as f:
    f.write(log_content)

# 3. Create Artifacts
def create_good_zip(filename):
    path = os.path.join(artifacts_dir, filename)
    with zipfile.ZipFile(path, 'w') as zf:
        zf.writestr("test.txt", "This is a test file.")

def create_bad_zip(filename):
    path = os.path.join(artifacts_dir, filename)
    with open(path, 'w') as f:
        f.write("This is not a valid zip archive, just text.")

create_good_zip("alpha-1.0.0.zip")
create_good_zip("alpha-2.0.0.zip")
create_good_zip("beta-1.0.0.zip")
create_bad_zip("beta-1.1.0.zip")  # Corrupted zip
create_good_zip("gamma-1.0.0.zip")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
