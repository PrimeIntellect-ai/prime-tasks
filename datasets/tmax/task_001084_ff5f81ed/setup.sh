#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy_project/src
    cd /home/user/legacy_project

    cat << 'EOF' > src/app.py
def main():
    print "Hello World"
EOF

    cat << 'EOF' > src/utils.py
def log(msg):
    print("Log: " + msg)
EOF

    cat << 'EOF' > src/helper.py
def help():
    print 'Help info'
EOF

    cat << 'EOF' > src/config.py
    print 'Config loaded'
EOF

    cat << 'EOF' > src/math.py
x = 5 + 2
EOF

    md5sum src/app.py src/utils.py src/config.py src/math.py > checksums.md5
    echo "00000000000000000000000000000000  src/helper.py" >> checksums.md5

    chmod -R 777 /home/user
