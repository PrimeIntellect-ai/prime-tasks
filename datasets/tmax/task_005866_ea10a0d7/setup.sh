#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip unzip zip g++ tar
pip3 install pytest

mkdir -p /home/user
cd /home/user

mkdir -p raw_docs_setup/notes/2023
mkdir -p raw_docs_setup/drafts

cat << 'EOF' > raw_docs_setup/system.log
[2023-10-01 10:00:00] INFO
System started successfully.
All modules loaded perfectly.
[2023-10-01 10:05:23] ERROR
Failed to connect to database.
Connection timeout on port 5432.
Retrying in 5 seconds...
[2023-10-01 10:06:00] WARNING
Disk space low on /dev/sda1.
Please free up some space.
[2023-10-01 10:12:45] ERROR
NullPointerException caught in MainModule.
Stack trace:
  at MainModule.run(MainModule.java:45)
  at Application.main(Application.java:20)
EOF

cat << 'EOF' > raw_docs_setup/notes/2023/meeting_notes.md
# Meeting Notes
Discussed the database timeout issues.
EOF

cat << 'EOF' > raw_docs_setup/drafts/api_v2.md
# API v2 Draft
Endpoints for the new user management system.
EOF

cd raw_docs_setup
zip -r ../docs_archive.zip *
cd ..
rm -rf raw_docs_setup

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
