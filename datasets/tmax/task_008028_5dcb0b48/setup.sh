#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project/data

    cat << 'EOF' > /home/user/project/build.sh
#!/bin/bash
echo '{"total_sum": 0}' > summary.json

for f in $(ls data/*.txt); do
  python3 processor.py $f &
done

wait
echo "Build complete."
EOF
    chmod +x /home/user/project/build.sh

    cat << 'EOF' > /home/user/project/processor.py
import sys
import json
import time

def main():
    if len(sys.argv) != 2:
        print("Usage: processor.py <filepath>")
        sys.exit(1)

    filepath = sys.argv[1]

    try:
        with open(filepath, 'r') as f:
            val = int(f.read().strip())
    except Exception as e:
        print(f"Error reading {filepath}: {e}")
        sys.exit(1)

    # Simulated processing time
    time.sleep(0.1)

    # Race condition: read, update, write without lock
    try:
        with open('summary.json', 'r') as f:
            data = json.load(f)
    except FileNotFoundError:
        data = {"total_sum": 0}

    data['total_sum'] += val

    time.sleep(0.1) # Exacerbate race condition

    with open('summary.json', 'w') as f:
        json.dump(data, f)

if __name__ == "__main__":
    main()
EOF

    echo 10 > "/home/user/project/data/file 1.txt"
    echo 20 > "/home/user/project/data/file 2.txt"
    echo 30 > "/home/user/project/data/file3.txt"
    echo 40 > "/home/user/project/data/file 4.txt"
    echo 50 > "/home/user/project/data/file5.txt"

    cd /home/user/project
    git init
    git config user.email "test@example.com"
    git config user.name "Test User"
    git add build.sh processor.py data/
    git commit -m "Initial commit"

    echo "DB_PASS=S3cr3t_P4ssW0rd_992!" > config.env
    git add config.env
    git commit -m "Add config"

    rm config.env
    git rm config.env
    git commit -m "Remove sensitive config"

    chmod -R 777 /home/user
