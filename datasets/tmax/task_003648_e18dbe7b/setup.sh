#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip procps
    pip3 install pytest

    mkdir -p /home/user/data_pipeline

    cat << 'EOF' > /home/user/data_pipeline/process_data.sh
#!/bin/bash

declare -a counts
while IFS= read -r line; do
    counts[$line]=$((counts[$line] + 1))
done < "$1"

for i in "${!counts[@]}"; do
    echo "$i: ${counts[$i]}"
done
EOF
    chmod +x /home/user/data_pipeline/process_data.sh

    cat << 'EOF' > /home/user/data_pipeline/upstream_service.py
import os
import time

file_path = '/home/user/data_pipeline/data.csv'
with open(file_path, 'w') as f:
    for i in range(1000):
        if i == 732:
            f.write("-1\n")
        else:
            f.write("10\n")

# Hold the file descriptor open after deletion
f = open(file_path, 'r')
os.remove(file_path)

while True:
    time.sleep(10)
EOF

    useradd -m -s /bin/bash user || true

    # Ensure the process starts if the environment runs bash
    cat << 'EOF' >> /home/user/.bashrc
if ! pgrep -f upstream_service.py > /dev/null; then
    python3 /home/user/data_pipeline/upstream_service.py &
    sleep 2
fi
EOF

    chmod -R 777 /home/user
