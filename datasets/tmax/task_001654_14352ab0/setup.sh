#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/pipeline/data

    cat << 'EOF' > /home/user/pipeline/legacy_filter.py
import sys
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    key = line.split('=')[0]
    if not key.startswith('DEBUG_') and not key.startswith('TEST_'):
        print(line)
EOF

    cat << 'EOF' > /home/user/pipeline/process.sh
#!/bin/bash

# Broken function: uses global 'line' variable which breaks the caller's while loop
filter_manifest() {
    input_file=$1
    output_file=$2
    > "$output_file"
    while read -r line; do
        # Call legacy python for now
        echo "$line" | python3 legacy_filter.py >> "$output_file"
    done < "$input_file"

    # Sort in place
    sort "$output_file" -o "$output_file"
}

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <old_manifest> <new_manifest>"
    exit 1
fi

OLD=$1
NEW=$2

# The variable bug: 'line' is used in the while loop below, but also implicitly in the helper if they wrote it purely in bash, 
# or they might run into issues. Actually, the prompt says the helper uses a global variable overwriting the main loop.
# Let's provide a skeleton that explicitly has this bug.

filter_manifest "$OLD" "/tmp/old_filtered.txt"
filter_manifest "$NEW" "/tmp/new_filtered.txt"

diff -u "/tmp/old_filtered.txt" "/tmp/new_filtered.txt" > build.patch
EOF
    chmod +x /home/user/pipeline/process.sh

    cat << 'EOF' > /home/user/pipeline/data/old_build.txt
VERSION=1.0.0
SIZE=1048576
DEBUG_FLAGS=1
MODULE_A=enabled
TEST_RUNS=42
MODULE_B=disabled
EOF

    cat << 'EOF' > /home/user/pipeline/data/new_build.txt
VERSION=1.0.1
SIZE=1050000
DEBUG_FLAGS=0
MODULE_A=enabled
TEST_RUNS=45
MODULE_B=enabled
NEW_MODULE=active
EOF

    chown -R user:user /home/user/pipeline
    chmod -R 777 /home/user
