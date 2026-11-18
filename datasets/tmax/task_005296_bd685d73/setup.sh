#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang-go
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/docs

cat << 'EOF' > /home/user/docs/setup.md
# Setup Guide
This is the setup guide.
EOF

cat << 'EOF' > /home/user/docs/api.md
# API Reference
List of endpoints.
EOF

cat << 'EOF' > /home/user/docs_build.log
[INFO] Starting build...
[ERROR] File: /home/user/docs/setup.md
[DETAILS] Missing metadata. Suggested JSON:
{
  "author": "alice",
  "status": "review"
}
[END]
[INFO] Processing other files...
[ERROR] File: /home/user/docs/api.md
[DETAILS] Missing metadata. Suggested JSON:
{
  "author": "bob",
  "status": "published"
}
[END]
[INFO] Build finished with errors.
EOF

touch /home/user/docs/updated_registry.csv

chmod -R 777 /home/user
