#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/src/nested

cat << 'EOF' > /home/user/deps.current
requests=2.18.4
numpy=1.16.0
scipy=1.0.0
six=1.10.0
urllib3=1.22
EOF

cat << 'EOF' > /home/user/deps.required
numpy>=1.16.0
six>=1.11.0
requests>=2.20.0
urllib3>=1.24.2
pandas>=0.24.0
scipy>=1.0.0
EOF

cat << 'EOF' > /home/user/src/main.py
print("Hello World")
EOF

cat << 'EOF' > /home/user/src/legacy.py
print "Legacy codebase"
EOF

cat << 'EOF' > /home/user/src/utils.py
x = 100L
EOF

cat << 'EOF' > /home/user/src/nested/helper.py
def foo(): pass
EOF

cat << 'EOF' > /home/user/src/nested/old.py
try:
    pass
except Exception, e:
    pass
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
