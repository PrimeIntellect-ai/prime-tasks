#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/pr_review

    cat << 'EOF' > /home/user/pr_review/solver.py
import sys
import time
import os

RATE_FILE = "/tmp/rate_limit.txt"

def check_rate_limit():
    now = time.time()
    if not os.path.exists(RATE_FILE):
        with open(RATE_FILE, "w") as f:
            f.write(f"{now}\n")
        return True

    with open(RATE_FILE, "r") as f:
        times = [float(x.strip()) for x in f.readlines() if x.strip()]

    # Clean up old entries (> 1 sec old)
    times = [t for t in times if now - t < 1.0]

    if len(times) >= 2:
        return False

    times.append(now)
    with open(RATE_FILE, "w") as f:
        for t in times:
            f.write(f"{t}\n")
    return True

if __name__ == "__main__":
    if not check_rate_limit():
        print("429 Rate Limit Exceeded")
        sys.exit(1)

    # Mock constraint satisfaction logic
    target = int(sys.argv[1])
    nums = [int(x) for x in sys.argv[2:]]
    print(f"Success: Solved subset sum for target {target}")
    sys.exit(0)
EOF

    cat << 'EOF' > /home/user/pr_review/build.sh
#!/bin/bash
echo "CONFIG_ARCH=x86" > config.env
EOF

    cat << 'EOF' > /home/user/pr_review/e2e_test.sh
#!/bin/bash
python3 /home/user/pr_review/solver.py 10 3 7 2
python3 /home/user/pr_review/solver.py 15 5 10 3
python3 /home/user/pr_review/solver.py 8 4 4 1
python3 /home/user/pr_review/solver.py 20 10 10 5
python3 /home/user/pr_review/solver.py 12 6 6 1
EOF

    chmod +x /home/user/pr_review/build.sh
    chmod +x /home/user/pr_review/e2e_test.sh

    chmod -R 777 /home/user
