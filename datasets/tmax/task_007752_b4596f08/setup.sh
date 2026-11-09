#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ruby coreutils gawk
pip3 install pytest

mkdir -p /home/user/project/src

cat << 'EOF' > /home/user/project/src/data.py
import os
threshold = int(os.environ.get("THRESHOLD", "0"))
if threshold != 24:
    print("Invalid threshold!")
    exit(1)
print("Data loaded.")
EOF

cat << 'EOF' > /home/user/project/src/transform.rb
workers = ENV["WORKERS"].to_i
if workers != 4
    puts "Invalid workers!"
    exit(1)
end
puts "Transformed."
EOF

PY_HASH=$(sha256sum /home/user/project/src/data.py | awk '{print $1}')
RB_HASH=$(sha256sum /home/user/project/src/transform.rb | awk '{print $1}')

cat << EOF > /home/user/project/main.pb
CHECKSUM src/data.py $PY_HASH
CHECKSUM src/transform.rb $RB_HASH
EXPR THRESHOLD = (50 + 10) * 2 / 5
EXPR WORKERS = 16 / (2 + 2)
BUILD python3 src/data.py
BUILD ruby src/transform.rb
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
