#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    git config --global user.email "dev@example.com"
    git config --global user.name "Dev"

    mkdir -p /home/user/prng_repo
    cd /home/user/prng_repo
    git init

    cat << 'EOF' > prng.py
def generate(seed, n):
    state = seed
    results = []
    for _ in range(n):
        state = (state * 1103515245 + 12345) & 0x7FFFFFFF
        results.append(state)
    return results
EOF

    git add prng.py
    git commit -m "Initial commit"
    git tag v1.0

    # Generate 200 commits
    for i in $(seq 1 200); do
        echo "Refactoring step $i" > "dummy_$i.txt"
        git add "dummy_$i.txt"

        if [ $i -eq 137 ]; then
            cat << 'EOF' > prng.py
def generate(seed, n):
    state = seed
    results = []
    for _ in range(n):
        # Optimized bitmask for 32-bit platforms
        state = (state * 1103515245 + 12345) & 0xFFFFFFFF
        results.append(state)
    return results
EOF
            git add prng.py
            git commit -m "Optimize bitmask and refactor step $i"
        else
            git commit -m "Refactoring step $i"
        fi
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
