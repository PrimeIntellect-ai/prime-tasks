#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make findutils coreutils
pip3 install pytest

mkdir -p /home/user/raw_logs

cat << 'EOF' > /home/user/raw_logs/log1.log
System started. Loading items: ABC-1234, DEF-5678.
Warning: item XYYZ-1234 is invalid length.
Processed XYZ-9999 successfully.
EOF

cat << 'EOF' > /home/user/raw_logs/log2.log
Another log entry here.
Retry loading ABC-1234.
Found legacy code LMN-0000 at the end.
Ignore lowercase def-5678 in raw text, only extract exact uppercase matches before normalizing!
EOF

cat << 'EOF' > /home/user/raw_logs/log3.log
XYZ-9999 is a duplicate.
Valid: QWE-1111.
Invalid: ABC-123.
Invalid: ABCD-1234.
Valid: ZZZ-9999
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
