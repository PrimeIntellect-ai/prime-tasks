#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

# Install C compiler and zlib development files
apt-get install -y gcc zlib1g-dev make gzip tar

# Create user
useradd -m -s /bin/bash user || true

# Setup initial state
mkdir -p /home/user/raw_docs_staging/folder_a/nested
mkdir -p /home/user/raw_docs_staging/folder_b

cat << 'EOF' > /home/user/raw_docs_staging/folder_a/sys.txt
Some random text
BEGIN_FRAGMENT
Chap: 01
Part: 01
Title: Introduction_To_System
Text:
Welcome to the system.
This is the first paragraph.
END_FRAGMENT
Junk line
EOF

cat << 'EOF' > /home/user/raw_docs_staging/folder_a/nested/sys2.txt
BEGIN_FRAGMENT
Chap: 01
Part: 02
Text:
This is the second part of the introduction.
END_FRAGMENT
EOF

cat << 'EOF' > /home/user/raw_docs_staging/folder_b/api.txt
BEGIN_FRAGMENT
Chap: 02
Part: 01
Title: API_Reference
Text:
The API has the following endpoints:
END_FRAGMENT
BEGIN_FRAGMENT
Chap: 02
Part: 02
Text:
- /v1/auth
- /v1/data
END_FRAGMENT
EOF

gzip /home/user/raw_docs_staging/folder_a/nested/sys2.txt
gzip /home/user/raw_docs_staging/folder_b/api.txt

cd /home/user/raw_docs_staging && tar -czf /home/user/legacy_docs.tar.gz .
cd /home/user
rm -rf /home/user/raw_docs_staging

# Set permissions
chmod -R 777 /home/user
